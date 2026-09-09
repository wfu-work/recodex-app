import 'dart:convert';

import '../models/bridge_models.dart';
import 'session_cache_backend.dart';

/// A cache scope is intentionally derived from the authenticated pairing, not
/// only from a thread id. The same thread id can exist on two Relay Spaces or
/// two target hosts and must never leak across those boundaries.
class SessionCacheScope {
  const SessionCacheScope({
    required this.key,
    required this.pairingId,
    required this.spaceId,
    required this.endpointId,
    required this.targetDeviceId,
  });

  final String key;
  final String pairingId;
  final String spaceId;
  final String endpointId;
  final String targetDeviceId;
}

class SessionCacheSnapshot {
  const SessionCacheSnapshot({
    this.sessions = const <SessionRecord>[],
    this.workspaces = const <WorkspaceInfo>[],
    this.eventsByThread = const <String, List<SessionEvent>>{},
    this.lastSequence = 0,
    this.syncedAt,
  });

  final List<SessionRecord> sessions;
  final List<WorkspaceInfo> workspaces;
  final Map<String, List<SessionEvent>> eventsByThread;
  final int lastSequence;
  final DateTime? syncedAt;

  bool get hasContent =>
      sessions.isNotEmpty ||
      workspaces.isNotEmpty ||
      eventsByThread.values.any((events) => events.isNotEmpty);
}

/// Persistent, bounded cache for the Relay catalog and selected timelines.
///
/// The controller remains the source of truth for live state. This service is
/// deliberately transport-agnostic: it only stores parsed model objects and a
/// last-known sequence, so an App Server revision or Relay reconnect can never
/// execute arbitrary cached commands.
class SessionCache {
  SessionCache({SessionCacheBackend? backend})
    : _backend = backend ?? createSessionCacheBackend();

  static const maxTimelineEvents = 500;
  static const maxInlineAttachmentBytes = 64 * 1024;
  static const maxIndexedTimelineThreads = 5;

  final SessionCacheBackend _backend;
  Future<void>? _opening;
  final _timelineRows = <String, Map<String, SessionCacheTimelineItem>>{};
  final _timelineRowAccess = <String, int>{};
  int _timelineRowClock = 0;

  Future<void> open() async {
    final pending = _opening;
    if (pending != null) {
      await pending;
      return;
    }
    final operation = _backend.open();
    _opening = operation;
    try {
      await operation;
    } catch (_) {
      // A platform plugin can be unavailable during the first frame (for
      // example before desktop plugin registration). Do not pin the service to
      // that failed Future; a later read/write should be allowed to retry.
      if (identical(_opening, operation)) _opening = null;
      rethrow;
    }
  }

  Future<SessionCacheSnapshot> load(
    SessionCacheScope scope, {
    String? timelineThreadId,
  }) async {
    try {
      await open();
      final catalog = await _backend.readCatalog(scope.key);
      final sessions = <SessionRecord>[];
      final workspaces = <WorkspaceInfo>[];
      var lastSequence = 0;
      DateTime? syncedAt;
      if (catalog != null) {
        sessions.addAll(_decodeSessions(catalog.sessionsJson));
        workspaces.addAll(_decodeWorkspaces(catalog.workspacesJson));
        lastSequence = catalog.lastSequence;
        syncedAt = catalog.syncedAtMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                catalog.syncedAtMillis!,
                isUtc: true,
              );
      }

      final eventsByThread = <String, List<SessionEvent>>{};
      // Catalog hydration is intentionally cheap. Only the task that was
      // selected before the previous app run is read here; other histories are
      // loaded on demand from [loadTimeline] when the user selects them.
      final requestedThreadId = timelineThreadId?.trim() ?? '';
      if (requestedThreadId.isNotEmpty) {
        final events = await _readTimelineEvents(scope, requestedThreadId);
        if (events.isNotEmpty) eventsByThread[requestedThreadId] = events;
      }
      return SessionCacheSnapshot(
        sessions: List.unmodifiable(sessions),
        workspaces: List.unmodifiable(workspaces),
        eventsByThread: _freezeEvents(eventsByThread),
        lastSequence: lastSequence,
        syncedAt: syncedAt,
      );
    } catch (_) {
      // Cache corruption or an unavailable platform database must never stop
      // Relay startup. The caller will continue with an empty snapshot.
      return const SessionCacheSnapshot();
    }
  }

  /// Loads one bounded timeline without decoding the whole catalog. This is
  /// used when switching tasks so a large cached history cannot block the
  /// sidebar or duplicate a full startup read.
  Future<List<SessionEvent>> loadTimeline(
    SessionCacheScope scope,
    String threadId,
  ) async {
    final id = threadId.trim();
    if (id.isEmpty) return const [];
    try {
      await open();
      return await _readTimelineEvents(scope, id);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCatalog(
    SessionCacheScope scope, {
    required List<SessionRecord> sessions,
    required List<WorkspaceInfo> workspaces,
    int? lastSequence,
    DateTime? syncedAt,
  }) async {
    try {
      await open();
      final previous = await _backend.readCatalog(scope.key);
      final row = SessionCacheCatalogRow(
        sessionsJson: jsonEncode(
          sessions
              .where((session) => session.id.trim().isNotEmpty)
              .map((session) => session.toJson())
              .toList(growable: false),
        ),
        workspacesJson: jsonEncode(
          workspaces
              .map((workspace) => workspace.toJson())
              .toList(growable: false),
        ),
        lastSequence: lastSequence ?? previous?.lastSequence ?? 0,
        syncedAtMillis: (syncedAt ?? _dateFromMillis(previous?.syncedAtMillis))
            ?.millisecondsSinceEpoch,
      );
      await _backend.writeCatalog(scope.key, row);
    } catch (_) {
      // Best-effort persistence. The in-memory state remains authoritative.
    }
  }

  Future<void> saveTimeline(
    SessionCacheScope scope,
    String threadId,
    List<SessionEvent> events,
  ) async {
    final id = threadId.trim();
    if (id.isEmpty) return;
    try {
      await open();
      final bounded = _boundedEvents(events);
      final rows = <SessionCacheTimelineItem>[];
      for (var index = 0; index < bounded.length; index += 1) {
        final event = bounded[index];
        rows.add(_timelineRow(event, index));
      }
      await _backend.replaceTimeline(scope.key, id, rows);
      _rememberTimelineRows(_timelineStorageKey(scope, id), {
        for (final row in rows) row.key: row,
      });
    } catch (_) {
      // See [saveCatalog].
    }
  }

  /// Persists a current timeline without rewriting unchanged rows.
  ///
  /// A full [saveTimeline] is reserved for an authoritative `thread.read`
  /// snapshot. Streaming events use this method so a long conversation does
  /// not cause hundreds of unchanged SQLite rows to be rewritten on every
  /// debounce tick. The service compares the bounded current snapshot with a
  /// small row index and sends only changed rows/deletions to the backend.
  Future<void> saveTimelineIncremental(
    SessionCacheScope scope,
    String threadId,
    List<SessionEvent> events,
  ) async {
    final id = threadId.trim();
    if (id.isEmpty) return;
    try {
      await open();
      final bounded = _boundedEvents(events);
      final desired = <String, SessionCacheTimelineItem>{};
      for (var index = 0; index < bounded.length; index += 1) {
        final row = _timelineRow(bounded[index], index);
        desired[row.key] = row;
      }
      final storageKey = _timelineStorageKey(scope, id);
      final known =
          _readTimelineRows(storageKey) ??
          {
            for (final row in await _backend.readTimeline(scope.key, id))
              row.key: row,
          };
      final changedRows = <String, SessionCacheTimelineItem>{};
      for (final row in desired.values) {
        final previous = known[row.key];
        if (previous == null ||
            previous.ordinal != row.ordinal ||
            previous.payload != row.payload) {
          changedRows[row.key] = row;
        }
      }

      final keysToRemove = known.keys
          .where((key) => !desired.containsKey(key))
          .toSet();
      if (changedRows.isNotEmpty || keysToRemove.isNotEmpty) {
        await _backend.upsertTimeline(
          scope.key,
          id,
          changedRows.values.toList(growable: false),
          removeKeys: keysToRemove,
        );
      }
      _rememberTimelineRows(storageKey, {
        for (final row in desired.values) row.key: row,
      });
    } catch (_) {
      // See [saveCatalog].
    }
  }

  /// Stable key shared by the in-memory diff and backend rows.
  static String timelineEventKey(SessionEvent event, int index) {
    final itemId = event.itemId?.trim() ?? '';
    final turnId = event.turnId?.trim() ?? '';
    if (itemId.isNotEmpty) return '$turnId|${event.kind}|$itemId';
    return '$turnId|${event.kind}|$index';
  }

  Future<void> updateSequence(
    SessionCacheScope scope, {
    required int sequence,
    DateTime? syncedAt,
  }) async {
    if (sequence < 0 && syncedAt == null) return;
    try {
      await open();
      final previous = await _backend.readCatalog(scope.key);
      if (previous == null) return;
      await _backend.writeCatalog(
        scope.key,
        SessionCacheCatalogRow(
          sessionsJson: previous.sessionsJson,
          workspacesJson: previous.workspacesJson,
          lastSequence: sequence >= 0 ? sequence : previous.lastSequence,
          syncedAtMillis: (syncedAt ?? _dateFromMillis(previous.syncedAtMillis))
              ?.millisecondsSinceEpoch,
        ),
      );
    } catch (_) {}
  }

  Future<void> close() async {
    try {
      await _backend.close();
    } catch (_) {}
    _opening = null;
    _timelineRows.clear();
    _timelineRowAccess.clear();
    _timelineRowClock = 0;
  }

  Future<List<SessionEvent>> _readTimelineEvents(
    SessionCacheScope scope,
    String threadId,
  ) async {
    final id = threadId.trim();
    final rows = await _backend.readTimeline(scope.key, id);
    _rememberTimelineRows(_timelineStorageKey(scope, id), {
      for (final row in rows)
        if (row.key.trim().isNotEmpty) row.key: row,
    });
    return rows
        .map((row) => _decodeEvent(row.payload))
        .whereType<SessionEvent>()
        .toList(growable: false);
  }

  Map<String, SessionCacheTimelineItem>? _readTimelineRows(String key) {
    final rows = _timelineRows[key];
    if (rows == null) return null;
    _timelineRowAccess[key] = ++_timelineRowClock;
    return rows;
  }

  void _rememberTimelineRows(
    String key,
    Map<String, SessionCacheTimelineItem> rows,
  ) {
    _timelineRows.remove(key);
    _timelineRows[key] = rows;
    _timelineRowAccess[key] = ++_timelineRowClock;
    while (_timelineRows.length > maxIndexedTimelineThreads) {
      String? oldest;
      var oldestAccess = 1 << 62;
      for (final entry in _timelineRowAccess.entries) {
        if (entry.key == key) continue;
        if (entry.value < oldestAccess) {
          oldest = entry.key;
          oldestAccess = entry.value;
        }
      }
      if (oldest == null) break;
      _timelineRows.remove(oldest);
      _timelineRowAccess.remove(oldest);
    }
  }

  List<SessionRecord> _decodeSessions(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return const [];
      final decoded = <SessionRecord>[];
      for (final item in value) {
        if (item is! Map) continue;
        try {
          final session = SessionRecord.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (session.id.trim().isNotEmpty) decoded.add(session);
        } catch (_) {
          // One malformed row must not hide the rest of a usable catalog.
        }
      }
      return decoded;
    } catch (_) {
      return const [];
    }
  }

  List<WorkspaceInfo> _decodeWorkspaces(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return const [];
      final decoded = <WorkspaceInfo>[];
      for (final item in value) {
        if (item is! Map) continue;
        try {
          decoded.add(WorkspaceInfo.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Keep valid workspace rows even when an old schema left one bad
          // value behind.
        }
      }
      return decoded;
    } catch (_) {
      return const [];
    }
  }

  SessionEvent? _decodeEvent(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map) return null;
      return SessionEvent.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  List<SessionEvent> _boundedEvents(List<SessionEvent> events) {
    if (events.length <= maxTimelineEvents) return List.of(events);
    // Keep the newest 500 events by default. Only reserve one slot for the
    // earliest user prompt when that prompt would otherwise fall outside the
    // window; this avoids dropping either the newest event or an available
    // recent item unnecessarily.
    final tail = events.sublist(events.length - maxTimelineEvents);
    final firstUser = events.firstWhere(
      (event) => event.kind == 'user',
      orElse: () => tail.first,
    );
    if (tail.any((event) => identical(event, firstUser))) return tail;
    final recent = events.sublist(events.length - (maxTimelineEvents - 1));
    return [firstUser, ...recent];
  }

  String _eventKey(SessionEvent event, int index) {
    return timelineEventKey(event, index);
  }

  SessionCacheTimelineItem _timelineRow(SessionEvent event, int ordinal) {
    return SessionCacheTimelineItem(
      key: _eventKey(event, ordinal),
      ordinal: ordinal,
      payload: jsonEncode(_cacheSafeEventJson(event)),
    );
  }

  String _timelineStorageKey(SessionCacheScope scope, String threadId) =>
      '${scope.key}\u0000${threadId.trim()}';

  Map<String, List<SessionEvent>> _freezeEvents(
    Map<String, List<SessionEvent>> source,
  ) {
    return Map<String, List<SessionEvent>>.unmodifiable({
      for (final entry in source.entries)
        entry.key: List<SessionEvent>.unmodifiable(entry.value),
    });
  }

  DateTime? _dateFromMillis(int? value) {
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  Map<String, dynamic> _cacheSafeEventJson(SessionEvent event) {
    // Full inline base64 payloads can be megabytes. The model-level
    // cache-safe serializer omits oversized data URLs before constructing the
    // JSON map, while retaining thumbnails and refreshable resource URLs.
    return event.toJson(cacheSafe: true);
  }
}
