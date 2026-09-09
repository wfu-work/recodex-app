/// A serialized catalog row stored by a [SessionCacheBackend].
class SessionCacheCatalogRow {
  const SessionCacheCatalogRow({
    required this.sessionsJson,
    required this.workspacesJson,
    required this.lastSequence,
    required this.syncedAtMillis,
  });

  final String sessionsJson;
  final String workspacesJson;
  final int lastSequence;
  final int? syncedAtMillis;
}

/// A single timeline item stored independently so a streaming delta can update
/// one row without rewriting a complete conversation blob.
class SessionCacheTimelineItem {
  const SessionCacheTimelineItem({
    required this.key,
    required this.ordinal,
    required this.payload,
  });

  final String key;
  final int ordinal;
  final String payload;
}

abstract class SessionCacheBackend {
  Future<void> open();

  Future<SessionCacheCatalogRow?> readCatalog(String scope);

  Future<List<SessionCacheTimelineItem>> readTimeline(
    String scope,
    String threadId,
  );

  Future<void> writeCatalog(String scope, SessionCacheCatalogRow row);

  Future<void> replaceTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items,
  );

  Future<void> upsertTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items, {
    Set<String> removeKeys = const <String>{},
  });

  Future<void> close();
}

/// A deterministic backend used by Web, tests, and native fallbacks when the
/// platform SQLite plugin cannot be opened. It has the same semantics as the
/// persistent backend but deliberately does not write credentials or files.
class MemorySessionCacheBackend implements SessionCacheBackend {
  final _catalog = <String, SessionCacheCatalogRow>{};
  final _timelines = <String, List<SessionCacheTimelineItem>>{};

  @override
  Future<void> open() async {}

  @override
  Future<SessionCacheCatalogRow?> readCatalog(String scope) async {
    return _catalog[scope];
  }

  @override
  Future<List<SessionCacheTimelineItem>> readTimeline(
    String scope,
    String threadId,
  ) async {
    final items = _timelines[_timelineKey(scope, threadId)] ?? const [];
    return List<SessionCacheTimelineItem>.of(items);
  }

  @override
  Future<void> writeCatalog(String scope, SessionCacheCatalogRow row) async {
    _catalog[scope] = row;
  }

  @override
  Future<void> replaceTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items,
  ) async {
    _timelines[_timelineKey(scope, threadId)] = List.of(items);
  }

  @override
  Future<void> upsertTimeline(
    String scope,
    String threadId,
    List<SessionCacheTimelineItem> items, {
    Set<String> removeKeys = const <String>{},
  }) async {
    final key = _timelineKey(scope, threadId);
    final current = <String, SessionCacheTimelineItem>{
      for (final item in _timelines[key] ?? const []) item.key: item,
    };
    for (final item in items) {
      current[item.key] = item;
    }
    for (final itemKey in removeKeys) {
      current.remove(itemKey);
    }
    final next = current.values.toList()..sort(_compareTimelineItems);
    _timelines[key] = next;
  }

  @override
  Future<void> close() async {}

  static String _timelineKey(String scope, String threadId) =>
      '$scope\u0000$threadId';

  static int _compareTimelineItems(
    SessionCacheTimelineItem left,
    SessionCacheTimelineItem right,
  ) {
    final ordinal = left.ordinal.compareTo(right.ordinal);
    return ordinal != 0 ? ordinal : left.key.compareTo(right.key);
  }
}
