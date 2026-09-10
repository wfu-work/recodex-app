import 'dart:convert';

import '../services/turn_file_changes.dart';

class WorkspaceInfo {
  const WorkspaceInfo({
    required this.name,
    required this.path,
    this.id = '',
    this.position,
    this.roots = const [],
  });

  final String name;
  final String path;
  final String id;
  final int? position;
  final List<String> roots;

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    final rawRoots = json['roots'];
    final roots = rawRoots is List
        ? rawRoots
              .map((root) {
                if (root is Map) return root['path']?.toString() ?? '';
                return root?.toString() ?? '';
              })
              .where((path) => path.trim().isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final rawPath = json['path']?.toString().trim() ?? '';
    return WorkspaceInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      path: rawPath.isNotEmpty ? rawPath : (roots.isEmpty ? '' : roots.first),
      position: (json['position'] as num?)?.toInt(),
      roots: roots,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    if (position != null) 'position': position,
    if (roots.isNotEmpty) 'roots': roots,
  };
}

/// The endpoint identity material shown while creating a Relay pairing.
///
/// The private seed is only kept in memory until the user saves the pairing;
/// the public key can be copied into relay-web when issuing a connection token.
class EndpointKeyMaterial {
  const EndpointKeyMaterial({required this.deviceKey, required this.publicKey});

  final String deviceKey;
  final String publicKey;
}

/// A saved Relay connection.  Tokens and the endpoint private key live in
/// this model so the controller can persist the complete profile in secure
/// storage and restore it atomically.
class PairingProfile {
  const PairingProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.spaceId,
    required this.deviceName,
    required this.deviceId,
    required this.targetDeviceId,
    required this.endpointType,
    required this.deviceKey,
    required this.endpointPublicKey,
    required this.pairingToken,
    required this.endpointGrant,
    required this.tokenExpiresAt,
    required this.grantExpiresAt,
    this.selectedWorkspaceName,
    this.selectedWorkspacePath,
    this.selectedSessionId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String spaceId;
  final String deviceName;
  final String deviceId;
  final String targetDeviceId;
  final String endpointType;
  final String deviceKey;
  final String endpointPublicKey;
  final String pairingToken;
  final String endpointGrant;
  final int tokenExpiresAt;
  final int grantExpiresAt;
  final String? selectedWorkspaceName;
  final String? selectedWorkspacePath;
  final String? selectedSessionId;
  final String? createdAt;
  final String? updatedAt;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      spaceId.trim().isNotEmpty &&
      targetDeviceId.trim().isNotEmpty &&
      deviceId.trim().isNotEmpty &&
      (pairingToken.trim().isNotEmpty || endpointGrant.trim().isNotEmpty);

  String get displayName {
    final value = name.trim();
    if (value.isNotEmpty) return value;
    final target = targetDeviceId.trim();
    return target.isEmpty ? '未命名配对' : target;
  }

  factory PairingProfile.fromJson(Map<String, dynamic> json) {
    return PairingProfile(
      id: _string(json['id']),
      name: _string(json['name']),
      baseUrl: _string(
        json['baseUrl'],
        fallback: 'ws://127.0.0.1:8788/v1/connect',
      ),
      spaceId: _string(json['spaceId']),
      deviceName: _string(json['deviceName'], fallback: 'Flutter phone'),
      deviceId: _string(json['deviceId']),
      targetDeviceId: _string(json['targetDeviceId']),
      endpointType: _string(json['endpointType'], fallback: 'app'),
      deviceKey: _string(json['deviceKey']),
      endpointPublicKey: _string(json['endpointPublicKey']),
      pairingToken: _string(json['pairingToken']),
      endpointGrant: _string(json['endpointGrant']),
      tokenExpiresAt: _int(json['tokenExpiresAt']),
      grantExpiresAt: _int(json['grantExpiresAt']),
      selectedWorkspaceName: _nullableString(json['selectedWorkspaceName']),
      selectedWorkspacePath: _nullableString(json['selectedWorkspacePath']),
      selectedSessionId: _nullableString(
        json['selectedSessionId'] ?? json['selected_session_id'],
      ),
      createdAt: _nullableString(json['createdAt']),
      updatedAt: _nullableString(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'spaceId': spaceId,
    'deviceName': deviceName,
    'deviceId': deviceId,
    'targetDeviceId': targetDeviceId,
    'endpointType': endpointType,
    'deviceKey': deviceKey,
    'endpointPublicKey': endpointPublicKey,
    'pairingToken': pairingToken,
    'endpointGrant': endpointGrant,
    'tokenExpiresAt': tokenExpiresAt,
    'grantExpiresAt': grantExpiresAt,
    if (selectedWorkspaceName != null)
      'selectedWorkspaceName': selectedWorkspaceName,
    if (selectedWorkspacePath != null)
      'selectedWorkspacePath': selectedWorkspacePath,
    if (selectedSessionId != null) 'selectedSessionId': selectedSessionId,
    if (createdAt != null) 'createdAt': createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };

  PairingProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? spaceId,
    String? deviceName,
    String? deviceId,
    String? targetDeviceId,
    String? endpointType,
    String? deviceKey,
    String? endpointPublicKey,
    String? pairingToken,
    String? endpointGrant,
    int? tokenExpiresAt,
    int? grantExpiresAt,
    String? selectedWorkspaceName,
    String? selectedWorkspacePath,
    String? selectedSessionId,
    String? createdAt,
    String? updatedAt,
    bool clearSelectedWorkspace = false,
    bool clearSelectedSession = false,
  }) {
    return PairingProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      spaceId: spaceId ?? this.spaceId,
      deviceName: deviceName ?? this.deviceName,
      deviceId: deviceId ?? this.deviceId,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      endpointType: endpointType ?? this.endpointType,
      deviceKey: deviceKey ?? this.deviceKey,
      endpointPublicKey: endpointPublicKey ?? this.endpointPublicKey,
      pairingToken: pairingToken ?? this.pairingToken,
      endpointGrant: endpointGrant ?? this.endpointGrant,
      tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
      grantExpiresAt: grantExpiresAt ?? this.grantExpiresAt,
      selectedWorkspaceName: clearSelectedWorkspace
          ? null
          : selectedWorkspaceName ?? this.selectedWorkspaceName,
      selectedWorkspacePath: clearSelectedWorkspace
          ? null
          : selectedWorkspacePath ?? this.selectedWorkspacePath,
      selectedSessionId: clearSelectedSession
          ? null
          : selectedSessionId ?? this.selectedSessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Lifecycle state projected onto the selected conversation timeline.
///
/// App Server exposes a thread-level `active/idle` state and a more precise
/// turn-level state. Keeping the projection explicit prevents a missing
/// `turn.started` event from making an in-flight turn look completed.
enum TimelineTaskStatus {
  unknown,
  loading,
  processing,
  waitingApproval,
  waitingUserInput,
  completed,
  failed,
  interrupted,
}

extension TimelineTaskStatusX on TimelineTaskStatus {
  bool get isActive =>
      this == TimelineTaskStatus.processing ||
      this == TimelineTaskStatus.waitingApproval ||
      this == TimelineTaskStatus.waitingUserInput;

  bool get isTerminal =>
      this == TimelineTaskStatus.completed ||
      this == TimelineTaskStatus.failed ||
      this == TimelineTaskStatus.interrupted;

  String get label => switch (this) {
    TimelineTaskStatus.processing => '正在思考',
    TimelineTaskStatus.waitingApproval => '等待审批',
    TimelineTaskStatus.waitingUserInput => '等待你的输入',
    TimelineTaskStatus.completed => '已完成',
    TimelineTaskStatus.failed => '执行失败',
    TimelineTaskStatus.interrupted => '已中断',
    TimelineTaskStatus.loading => '状态同步中…',
    TimelineTaskStatus.unknown => '状态同步中…',
  };
}

/// Guards lifecycle values read from eventually-consistent thread snapshots.
///
/// A metadata-only read can legitimately return `unknown` while the desktop
/// App Server is still persisting a turn.  It can also expose a previous
/// terminal turn while a newer turn is already running.  The guard keeps the
/// last trusted value until a snapshot contains positive evidence that it is
/// safe to change, and rejects a lower-quality terminal downgrade without a
/// new turn identity.
class TimelineSnapshotGuard {
  TimelineTaskStatus _trustedStatus = TimelineTaskStatus.unknown;
  String? _trustedTurnId;
  int? _lastRevision;

  TimelineTaskStatus get trustedStatus => _trustedStatus;
  String? get trustedTurnId => _trustedTurnId;
  int? get lastRevision => _lastRevision;

  void reset() {
    _trustedStatus = TimelineTaskStatus.unknown;
    _trustedTurnId = null;
    _lastRevision = null;
  }

  /// Keeps the trusted lifecycle while forgetting the previous turn identity.
  /// Used when a new active turn is observed before its id is available.
  void clearTurnIdentity() {
    _trustedTurnId = null;
  }

  /// A Relay/App Server reconnect starts a fresh revision namespace. Preserve
  /// the visible lifecycle but allow the new connector to establish its first
  /// snapshot revision without being rejected as stale.
  void resetRevision() {
    _lastRevision = null;
  }

  /// Records an event-driven lifecycle value, which is stronger than a
  /// persisted snapshot and therefore does not participate in revision
  /// ordering.
  void recordTrusted(TimelineTaskStatus status, {String? turnId}) {
    if (status == TimelineTaskStatus.unknown ||
        status == TimelineTaskStatus.loading) {
      return;
    }
    _trustedStatus = status;
    final normalizedTurnId = turnId?.trim();
    if (normalizedTurnId != null && normalizedTurnId.isNotEmpty) {
      _trustedTurnId = normalizedTurnId;
    }
  }

  /// Returns whether [status] may replace the current trusted snapshot.
  bool acceptSnapshot(
    TimelineTaskStatus status, {
    String? turnId,
    int? revision,
  }) {
    if (revision != null &&
        _lastRevision != null &&
        revision <= _lastRevision!) {
      return false;
    }
    if (revision != null) _lastRevision = revision;

    final normalizedTurnId = turnId?.trim();
    final hasNewTurn =
        normalizedTurnId != null &&
        normalizedTurnId.isNotEmpty &&
        normalizedTurnId != _trustedTurnId;

    // Unknown/loading is a transport or hydration condition, not a lifecycle
    // transition. Never erase an active or terminal value with it.
    if (status == TimelineTaskStatus.unknown ||
        status == TimelineTaskStatus.loading) {
      if (_trustedStatus.isActive || _trustedStatus.isTerminal) return false;
      _trustedStatus = status;
      if (normalizedTurnId != null && normalizedTurnId.isNotEmpty) {
        _trustedTurnId = normalizedTurnId;
      }
      return true;
    }

    if (_trustedStatus.isActive && status.isTerminal) {
      // While a turn is visibly active, a terminal snapshot is only valid if
      // it names that same turn.  Missing ids are ambiguous and therefore
      // wait for a later authoritative snapshot/event.
      if (normalizedTurnId == null || normalizedTurnId.isEmpty) return false;
      if (_trustedTurnId == null || normalizedTurnId != _trustedTurnId) {
        return false;
      }
    }

    // A completed turn cannot become interrupted/failed merely because an
    // older snapshot arrived out of order. A different turn id is the only
    // snapshot-level evidence that a new terminal state is legitimate.
    if (_trustedStatus.isTerminal &&
        status.isTerminal &&
        status != _trustedStatus &&
        (_trustedTurnId == null || !hasNewTurn)) {
      return false;
    }

    _trustedStatus = status;
    if (normalizedTurnId != null && normalizedTurnId.isNotEmpty) {
      _trustedTurnId = normalizedTurnId;
    }
    return true;
  }
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.workspace,
    required this.prompt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.recencyAt = '',
    this.projectId = '',
    this.title = '',
    this.isPinned = false,
    this.isArchived = false,
  });

  final String id;
  final String workspace;
  final String prompt;
  final String status;
  final String createdAt;
  final String updatedAt;

  /// App Server's sidebar-oriented last-access/activity timestamp. Older
  /// servers do not return it, in which case [recencyAtDate] falls back to
  /// [updatedAt].
  final String recencyAt;
  final String projectId;

  /// Official Codex thread name. This is a generated, user-facing title and
  /// is preferred over [prompt] when it is available.
  final String title;
  final bool isPinned;
  final bool isArchived;

  SessionRecord copyWith({
    String? id,
    String? workspace,
    String? prompt,
    String? status,
    String? createdAt,
    String? updatedAt,
    String? recencyAt,
    String? projectId,
    String? title,
    bool? isPinned,
    bool? isArchived,
  }) {
    return SessionRecord(
      id: id ?? this.id,
      workspace: workspace ?? this.workspace,
      prompt: prompt ?? this.prompt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      recencyAt: recencyAt ?? this.recencyAt,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  /// A stable label for compact task navigation. Codex may not provide a
  /// title for older threads, so fall back to the first prompt and finally
  /// the thread id instead of rendering an empty row.
  String get displayTitle {
    final named = _cleanTaskTitle(title);
    if (named.isNotEmpty) return named;
    final value = _cleanTaskTitle(prompt);
    if (value.isNotEmpty) return value;
    return id.trim().isEmpty ? '未命名任务' : id;
  }

  bool get isRunning {
    final value = status
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return value == 'running' ||
        value == 'active' ||
        value == 'in_progress' ||
        value == 'inprogress' ||
        value == 'processing' ||
        value == 'queued' ||
        value == 'starting' ||
        value == 'pending' ||
        value == 'executing' ||
        value == 'working' ||
        value == 'waitingonapproval' ||
        value == 'waiting_on_approval' ||
        value == 'waitingonuserinput' ||
        value == 'waiting_on_user_input';
  }

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final status = rawStatus is Map
        ? (rawStatus['type'] ?? rawStatus['state'] ?? rawStatus['status'] ?? '')
              .toString()
        : rawStatus?.toString() ?? '';
    final archived = _jsonBool(
      json['isArchived'] ?? json['is_archived'] ?? json['archived'],
    );
    return SessionRecord(
      id: json['id'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      prompt: json['prompt'] as String? ?? json['preview'] as String? ?? '',
      status: status,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      recencyAt:
          json['recencyAt'] as String? ?? json['recency_at'] as String? ?? '',
      projectId:
          json['projectId'] as String? ?? json['project_id'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      isPinned: _jsonBool(
        json['isPinned'] ?? json['is_pinned'] ?? json['pinned'],
      ),
      isArchived: archived || status.trim().toLowerCase() == 'archived',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspace': workspace,
    'prompt': prompt,
    'status': status,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (recencyAt.isNotEmpty) 'recencyAt': recencyAt,
    if (projectId.isNotEmpty) 'projectId': projectId,
    if (title.isNotEmpty) 'title': title,
    if (isPinned) 'isPinned': true,
    if (isArchived) 'isArchived': true,
  };

  DateTime get updatedAtDate {
    return _sessionDate(updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime get recencyAtDate {
    final parsed = _sessionDate(recencyAt);
    if (parsed != null) return parsed;
    return updatedAtDate;
  }
}

/// The single task ordering contract shared by the controller and sidebar
/// widgets. `recencyAt` matches the current Codex sidebar; the remaining
/// fields make equal timestamps deterministic across refreshes and pages.
int compareSessionRecords(SessionRecord left, SessionRecord right) {
  final recency = right.recencyAtDate.compareTo(left.recencyAtDate);
  if (recency != 0) return recency;
  final updated = right.updatedAtDate.compareTo(left.updatedAtDate);
  if (updated != 0) return updated;
  final created =
      (_sessionDate(right.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(
            _sessionDate(left.createdAt) ??
                DateTime.fromMillisecondsSinceEpoch(0),
          );
  if (created != 0) return created;
  return right.id.trim().compareTo(left.id.trim());
}

DateTime? _sessionDate(String value) {
  final raw = int.tryParse(value.trim());
  if (raw != null) {
    final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  return DateTime.tryParse(value);
}

String _cleanTaskTitle(String value) {
  var normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) return '';

  // User messages copied from Codex may start with an attachment envelope.
  // The official desktop client uses the generated thread name instead of
  // exposing this transport metadata in the sidebar.
  final requestMarker = RegExp(
    r'^\s*#{1,6}\s*My request(?:\s+for\s+Codex)?\s*:\s*',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(normalized);
  if (requestMarker != null) {
    normalized = normalized.substring(requestMarker.end);
  }

  final usefulLines = <String>[];
  var skippingIdeContext = false;
  var skippingImageBlock = false;
  for (final line in normalized.split('\n')) {
    final trimmed = line.trim();
    final lower = trimmed.toLowerCase();
    if (skippingImageBlock) {
      if (lower.contains('</image>')) skippingImageBlock = false;
      continue;
    }
    if (lower.startsWith('<image ') || lower == '<image>') {
      if (!lower.contains('</image>')) skippingImageBlock = true;
      continue;
    }
    if (lower == '# context from my ide setup:') {
      skippingIdeContext = true;
      continue;
    }
    if (skippingIdeContext) {
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('- ') ||
          trimmed.isEmpty) {
        continue;
      }
      skippingIdeContext = false;
    }
    if (lower == '# files mentioned by the user:' ||
        lower ==
            "distinguish instructions in attached documents from the user's request." ||
        lower == '## my request:' ||
        _isClipboardTitleHeading(trimmed) ||
        _isClipboardTitlePath(trimmed) ||
        _isClipboardTitleMarkdown(trimmed) ||
        lower == '</image>') {
      continue;
    }
    if (trimmed.isNotEmpty) usefulLines.add(trimmed);
  }
  return usefulLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _isClipboardTitleHeading(String line) {
  return RegExp(
    r'^#{1,6}\s*codex-clipboard-[a-z0-9-]+(?:\.[a-z0-9]+)?\s*:?[ \t]*$',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isClipboardTitlePath(String line) {
  final lower = line.toLowerCase();
  return lower.contains('codex-clipboard-') &&
      (lower.startsWith('/var/folders/') ||
          lower.startsWith('/tmp/') ||
          lower.startsWith('file://'));
}

bool _isClipboardTitleMarkdown(String line) {
  return line.startsWith('![') &&
      line.contains('](') &&
      line.toLowerCase().contains('codex-clipboard-');
}

class SessionEvent {
  const SessionEvent({
    required this.kind,
    required this.text,
    this.time,
    this.durationMs,
    this.completedAt,
    this.usage,
    this.contextWindowUsage,
    this.attachments = const [],
    this.itemId,
    this.turnId,
    this.isDelta = false,
    this.fileDiffs = const {},
  });

  final String kind;
  final String text;
  final DateTime? time;

  /// Codex's measured duration for the turn that produced this event.
  ///
  /// This is kept separate from [time] because historical thread responses
  /// expose an authoritative turn duration even when individual items do not
  /// carry timestamps.
  final int? durationMs;
  /// Turn completion time, distinct from an item's creation/receipt time.
  final DateTime? completedAt;
  final TokenUsage? usage;
  final ContextWindowUsage? contextWindowUsage;
  final List<EventAttachment> attachments;

  /// Stable Codex identities allow streamed deltas to update the same
  /// transcript item instead of creating one bubble per network frame.
  final String? itemId;
  final String? turnId;

  /// True for a transport delta. Snapshot events with the same item id
  /// replace the accumulated text; deltas append to it.
  final bool isDelta;

  /// File patches belonging to this item/turn, retained in the timeline cache.
  /// An empty patch means that only the path is known (e.g. a binary file).
  final Map<String, String> fileDiffs;

  SessionEvent copyWith({
    String? kind,
    String? text,
    DateTime? time,
    int? durationMs,
    DateTime? completedAt,
    TokenUsage? usage,
    ContextWindowUsage? contextWindowUsage,
    List<EventAttachment>? attachments,
    String? itemId,
    String? turnId,
    bool? isDelta,
    Map<String, String>? fileDiffs,
  }) {
    return SessionEvent(
      kind: kind ?? this.kind,
      text: text ?? this.text,
      time: time ?? this.time,
      durationMs: durationMs ?? this.durationMs,
      completedAt: completedAt ?? this.completedAt,
      usage: usage ?? this.usage,
      contextWindowUsage: contextWindowUsage ?? this.contextWindowUsage,
      attachments: attachments ?? this.attachments,
      itemId: itemId ?? this.itemId,
      turnId: turnId ?? this.turnId,
      isDelta: isDelta ?? this.isDelta,
      fileDiffs: fileDiffs ?? this.fileDiffs,
    );
  }

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      kind: json['kind'] as String? ?? 'event',
      text: json['text'] as String? ?? json['raw'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? ''),
      durationMs: _jsonNullableInt(json['durationMs'] ?? json['duration_ms']),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      usage: json['usage'] is Map
          ? TokenUsage.fromJson((json['usage'] as Map).cast<String, dynamic>())
          : null,
      contextWindowUsage: ContextWindowUsage.tryParse(json['contextWindowUsage']),
      attachments: ((json['attachments'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => EventAttachment.fromJson(item.cast<String, dynamic>()))
          .toList(),
      itemId: json['itemId'] as String? ?? json['item_id'] as String?,
      turnId: json['turnId'] as String? ?? json['turn_id'] as String?,
      isDelta: json['isDelta'] == true || json['is_delta'] == true,
      fileDiffs: TurnFileChanges.fromJson(json['fileDiffs']),
    );
  }

  Map<String, dynamic> toJson({bool cacheSafe = false}) => {
    'kind': kind,
    'text': text,
    if (time != null) 'time': time!.toUtc().toIso8601String(),
    if (durationMs != null) 'durationMs': durationMs,
    if (completedAt != null) 'completedAt': completedAt!.toUtc().toIso8601String(),
    if (usage != null) 'usage': usage!.toJson(),
    if (contextWindowUsage != null)
      'contextWindowUsage': contextWindowUsage!.toJson(),
    if (attachments.isNotEmpty)
      'attachments': attachments
          .map((item) => item.toJson(cacheSafe: cacheSafe))
          .toList(),
    if (itemId != null && itemId!.trim().isNotEmpty) 'itemId': itemId,
    if (turnId != null && turnId!.trim().isNotEmpty) 'turnId': turnId,
    if (isDelta) 'isDelta': true,
    if (fileDiffs.isNotEmpty) 'fileDiffs': fileDiffs,
  };
}

class EventAttachment {
  const EventAttachment({
    required this.type,
    required this.mime,
    this.dataUrl = '',
    this.thumbnailDataUrl = '',
    this.resourceUrl = '',
    this.expiresAt,
  });

  final String type;
  final String mime;

  /// Legacy inline payload. New events should use [thumbnailDataUrl] for the
  /// initial render and [resourceUrl] for the full-resolution image.
  final String dataUrl;
  final String thumbnailDataUrl;
  final String resourceUrl;
  final String? expiresAt;

  EventAttachment copyWith({
    String? type,
    String? mime,
    String? dataUrl,
    String? thumbnailDataUrl,
    String? resourceUrl,
    String? expiresAt,
  }) {
    return EventAttachment(
      type: type ?? this.type,
      mime: mime ?? this.mime,
      dataUrl: dataUrl ?? this.dataUrl,
      thumbnailDataUrl: thumbnailDataUrl ?? this.thumbnailDataUrl,
      resourceUrl: resourceUrl ?? this.resourceUrl,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  bool get hasImageSource =>
      thumbnailDataUrl.trim().isNotEmpty ||
      dataUrl.trim().isNotEmpty ||
      resourceUrl.trim().isNotEmpty;

  factory EventAttachment.fromJson(Map<String, dynamic> json) {
    return EventAttachment(
      type: json['type'] as String? ?? '',
      mime: json['mime'] as String? ?? json['mimeType'] as String? ?? '',
      dataUrl: json['dataUrl'] as String? ?? json['data_url'] as String? ?? '',
      thumbnailDataUrl:
          json['thumbnailDataUrl'] as String? ??
          json['thumbnail_data_url'] as String? ??
          json['thumbnail'] as String? ??
          '',
      resourceUrl:
          json['resourceUrl'] as String? ??
          json['resource_url'] as String? ??
          json['url'] as String? ??
          '',
      expiresAt:
          json['expiresAt']?.toString() ?? json['expires_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson({bool cacheSafe = false}) => {
    'type': type,
    'mime': mime,
    if (dataUrl.isNotEmpty && _keepInlinePayload(dataUrl, cacheSafe))
      'dataUrl': dataUrl,
    if (thumbnailDataUrl.isNotEmpty &&
        _keepInlinePayload(thumbnailDataUrl, cacheSafe))
      'thumbnailDataUrl': thumbnailDataUrl,
    if (resourceUrl.isNotEmpty) 'resourceUrl': resourceUrl,
    if (expiresAt != null && expiresAt!.trim().isNotEmpty)
      'expiresAt': expiresAt,
  };

  static bool _keepInlinePayload(String value, bool cacheSafe) {
    if (!cacheSafe || !value.startsWith('data:')) return true;
    return utf8.encode(value).length <= 64 * 1024;
  }
}

enum TokenUsageScope { turn, thread, lastCall, unknown }

/// The most recent model context, separate from cumulative token consumption.
class ContextWindowUsage {
  const ContextWindowUsage({
    required this.usedTokens,
    required this.maxTokens,
    this.updatedAt,
  }) : assert(usedTokens >= 0),
       assert(maxTokens > 0);

  final int usedTokens;
  final int maxTokens;
  final DateTime? updatedAt;

  double get fraction => (usedTokens / maxTokens).clamp(0.0, 1.0);
  int get percent => (fraction * 100).round();

  static ContextWindowUsage? tryParse(Object? value) {
    if (value is! Map) return null;
    final used = value['usedTokens'];
    final limit = value['maxTokens'];
    if (used is! int || used < 0 || limit is! int || limit <= 0) return null;
    return ContextWindowUsage(
      usedTokens: used,
      maxTokens: limit,
      updatedAt: DateTime.tryParse(value['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'usedTokens': usedTokens,
    'maxTokens': maxTokens,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is ContextWindowUsage &&
      usedTokens == other.usedTokens &&
      maxTokens == other.maxTokens &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(usedTokens, maxTokens, updatedAt);
}

class TokenUsage {
  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    this.scope = TokenUsageScope.unknown,
    this.hasBreakdown = true,
    this.cachedInputTokens,
    this.reasoningOutputTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final TokenUsageScope scope;
  final bool hasBreakdown;
  final int? cachedInputTokens;
  final int? reasoningOutputTokens;

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      inputTokens: _jsonInt(json['inputTokens'] ?? json['input_tokens']),
      outputTokens: _jsonInt(json['outputTokens'] ?? json['output_tokens']),
      totalTokens: _jsonInt(json['totalTokens'] ?? json['total_tokens']),
      scope: TokenUsageScope.values.firstWhere(
        (value) => value.name == json['scope'],
        orElse: () => TokenUsageScope.unknown,
      ),
      hasBreakdown: json['hasBreakdown'] as bool? ?? true,
      cachedInputTokens: _jsonNullableInt(json['cachedInputTokens'] ?? json['cached_input_tokens']),
      reasoningOutputTokens: _jsonNullableInt(json['reasoningOutputTokens'] ?? json['reasoning_output_tokens']),
    );
  }

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
    'scope': scope.name,
    'hasBreakdown': hasBreakdown,
    if (cachedInputTokens != null) 'cachedInputTokens': cachedInputTokens,
    if (reasoningOutputTokens != null) 'reasoningOutputTokens': reasoningOutputTokens,
  };
}

class GitSnapshot {
  const GitSnapshot({
    required this.branch,
    required this.status,
    required this.stat,
    required this.numstat,
    required this.diff,
    required this.log,
    this.fileDiffs = const {},
  });

  final String branch;
  final String status;
  final String stat;
  final String numstat;
  final String diff;
  final String log;
  final Map<String, String> fileDiffs;

  factory GitSnapshot.fromJson(Map<String, dynamic> json) {
    return GitSnapshot(
      branch: json['branch'] as String? ?? '',
      status: json['status'] as String? ?? '',
      stat: json['stat'] as String? ?? '',
      numstat: json['numstat'] as String? ?? '',
      diff: json['diff'] as String? ?? '',
      log: json['log'] as String? ?? '',
      fileDiffs: TurnFileChanges.fromJson(json['fileDiffs']),
    );
  }

  /// Capture patches from the answer that opened review. A turn-wide diff
  /// supersedes that turn's item patches so edits are not counted twice.
  factory GitSnapshot.fromEvents(Iterable<SessionEvent> events) {
    final items = <String, Map<String, Map<String, String>>>{};
    final turns = <String, Map<String, String>>{};
    var index = 0;
    for (final event in events) {
      final turn = event.turnId ?? '';
      if (event.itemId?.startsWith('turn-diff:') == true) {
        turns[turn] = event.fileDiffs;
      } else if (event.fileDiffs.isNotEmpty) {
        (items[turn] ??= {})[event.itemId ?? 'item:${index++}'] =
            event.fileDiffs;
      }
    }
    final files = <String, String>{};
    for (final turn in {...items.keys, ...turns.keys}) {
      final patches = turns.containsKey(turn)
          ? [turns[turn]!]
          : items[turn]!.values;
      for (final patch in patches) {
        for (final entry in patch.entries) {
          final old = files[entry.key];
          files[entry.key] = old == null || old.isEmpty
              ? entry.value
              : entry.value.isEmpty
              ? old
              : '$old\n${entry.value}';
        }
      }
    }
    return GitSnapshot(
      branch: '',
      status: '',
      stat: '',
      log: '',
      numstat: TurnFileChanges.numstat(files),
      diff: files.values.join('\n'),
      fileDiffs: Map.unmodifiable(files),
    );
  }

  List<String> get _statPaths => numstat
      .split('\n')
      .map((line) => line.split('\t'))
      .where((parts) => parts.length >= 3)
      .map((parts) => parts.sublist(2).join('\t'))
      .toList();

  String resolveFilePath(String path) =>
      TurnFileChanges.resolvePath([...fileDiffs.keys, ..._statPaths], path) ??
      path;

  String patchForFile(String path) {
    if (fileDiffs.isNotEmpty) {
      final key = TurnFileChanges.resolvePath(fileDiffs.keys, path);
      // A path-only item must not fall back to another file's patch.
      return key == null ? '' : fileDiffs[key]!;
    }
    final legacyFiles = TurnFileChanges.fromUnifiedDiff(diff);
    if (legacyFiles.isNotEmpty) {
      final key = TurnFileChanges.resolvePath(legacyFiles.keys, path);
      return key == null ? '' : legacyFiles[key]!;
    }
    // Hunk-only legacy content is attributable only with one known file.
    if (_statPaths.length == 1 &&
        TurnFileChanges.resolvePath(_statPaths, path) != null &&
        diff.contains(RegExp(r'^@@ ', multiLine: true))) {
      return diff;
    }
    return '';
  }
}

class ComposerContext {
  const ComposerContext({
    required this.transport,
    required this.model,
    required this.models,
    required this.modelLabels,
    required this.reasoningEffort,
    required this.reasoningEfforts,
    required this.approvalPolicy,
    required this.requireConfirmGitWrite,
    required this.branch,
    required this.bridgeVersion,
    required this.codexBinary,
    required this.codexVersion,
    required this.apiKeyConfigured,
    required this.usage,
    this.modelReasoningEfforts = const {},
    this.modelDefaultReasoningEfforts = const {},
  });

  final String transport;
  final String model;
  final List<String> models;

  /// Human-readable names keyed by the model identifier sent to Codex.
  ///
  /// The App Server exposes both a stable `model` value and a presentation
  /// `displayName`. Keeping them separate means the picker can show the same
  /// names as Codex while turn/start still receives the canonical identifier.
  final Map<String, String> modelLabels;
  final String reasoningEffort;

  /// Reasoning levels advertised by the App Server for each model id.
  ///
  /// This is intentionally model-scoped: Codex models do not all expose the
  /// same effort range (for example, some support `ultra` while others stop at
  /// `xhigh`). An empty entry means that the host did not advertise the
  /// capability, so the UI should not invent a fallback list.
  final Map<String, List<String>> modelReasoningEfforts;

  /// Default reasoning level advertised by the App Server for each model id.
  final Map<String, String> modelDefaultReasoningEfforts;
  final List<String> reasoningEfforts;
  final String approvalPolicy;
  final bool requireConfirmGitWrite;
  final String branch;
  final String bridgeVersion;
  final String codexBinary;
  final String codexVersion;
  final bool apiKeyConfigured;
  final UsageOverview usage;

  ComposerContext copyWith({
    String? transport,
    String? model,
    List<String>? models,
    Map<String, String>? modelLabels,
    String? reasoningEffort,
    Map<String, List<String>>? modelReasoningEfforts,
    Map<String, String>? modelDefaultReasoningEfforts,
    List<String>? reasoningEfforts,
    String? approvalPolicy,
    bool? requireConfirmGitWrite,
    String? branch,
    String? bridgeVersion,
    String? codexBinary,
    String? codexVersion,
    bool? apiKeyConfigured,
    UsageOverview? usage,
  }) {
    return ComposerContext(
      transport: transport ?? this.transport,
      model: model ?? this.model,
      models: models ?? this.models,
      modelLabels: modelLabels ?? this.modelLabels,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      modelReasoningEfforts:
          modelReasoningEfforts ?? this.modelReasoningEfforts,
      modelDefaultReasoningEfforts:
          modelDefaultReasoningEfforts ?? this.modelDefaultReasoningEfforts,
      reasoningEfforts: reasoningEfforts ?? this.reasoningEfforts,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      requireConfirmGitWrite:
          requireConfirmGitWrite ?? this.requireConfirmGitWrite,
      branch: branch ?? this.branch,
      bridgeVersion: bridgeVersion ?? this.bridgeVersion,
      codexBinary: codexBinary ?? this.codexBinary,
      codexVersion: codexVersion ?? this.codexVersion,
      apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
      usage: usage ?? this.usage,
    );
  }

  String modelLabel(String value) => modelLabels[value] ?? value;

  factory ComposerContext.fromJson(Map<String, dynamic> json) {
    final parsedModels = <String>[];
    final parsedLabels = <String, String>{};
    final parsedReasoningEfforts = <String, List<String>>{};
    final parsedDefaultReasoningEfforts = <String, String>{};
    final rawModels = json['models'];
    if (rawModels is List) {
      for (final raw in rawModels) {
        String? id;
        String? label;
        Map<Object?, Object?>? map;
        if (raw is Map) {
          map = raw.cast<Object?, Object?>();
          id = map['model']?.toString().trim();
          if (id == null || id.isEmpty) id = map['id']?.toString().trim();
          label = map['displayName']?.toString().trim();
          if (map['hidden'] == true) continue;
        } else {
          id = raw?.toString().trim();
        }
        if (id == null || id.isEmpty || parsedModels.contains(id)) continue;
        parsedModels.add(id);
        parsedLabels[id] = label == null || label.isEmpty ? id : label;

        final supported = parseReasoningEfforts(
          map?['supportedReasoningEfforts'] ??
              map?['supported_reasoning_efforts'] ??
              map?['reasoningEfforts'] ??
              map?['reasoning_efforts'],
        );
        if (supported.isNotEmpty) parsedReasoningEfforts[id] = supported;
        final defaultEffort = _readNonEmptyString(
          map?['defaultReasoningEffort'] ?? map?['default_reasoning_effort'],
        );
        if (defaultEffort != null) {
          parsedDefaultReasoningEfforts[id] = defaultEffort;
        }
      }
    }
    final rawLabels = json['modelLabels'];
    if (rawLabels is Map) {
      for (final entry in rawLabels.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) parsedLabels[key] = value;
      }
    }
    final topLevelReasoningEfforts = parseReasoningEfforts(
      json['reasoningEfforts'] ?? json['reasoning_efforts'],
    );
    final currentModel = _readNonEmptyString(json['model']) ?? '';
    if (currentModel.isNotEmpty &&
        topLevelReasoningEfforts.isNotEmpty &&
        !parsedReasoningEfforts.containsKey(currentModel)) {
      parsedReasoningEfforts[currentModel] = topLevelReasoningEfforts;
    }
    final currentReasoningEfforts =
        parsedReasoningEfforts[currentModel] ?? topLevelReasoningEfforts;
    final requestedReasoning =
        _readNonEmptyString(
          json['reasoningEffort'] ?? json['reasoning_effort'],
        ) ??
        '';
    final advertisedDefault = parsedDefaultReasoningEfforts[currentModel];
    final reasoningEffort = _resolveReasoningEffort(
      requested: requestedReasoning,
      available: currentReasoningEfforts,
      advertisedDefault: advertisedDefault,
    );
    return ComposerContext(
      transport: json['transport'] as String? ?? 'Local',
      model: currentModel,
      models: parsedModels,
      modelLabels: parsedLabels,
      reasoningEffort: reasoningEffort,
      reasoningEfforts: currentReasoningEfforts,
      modelReasoningEfforts: parsedReasoningEfforts,
      modelDefaultReasoningEfforts: parsedDefaultReasoningEfforts,
      approvalPolicy: json['approvalPolicy'] as String? ?? 'on-request',
      requireConfirmGitWrite: json['requireConfirmGitWrite'] as bool? ?? true,
      branch: json['branch'] as String? ?? '',
      bridgeVersion:
          json['bridgeVersion'] as String? ?? json['version'] as String? ?? '',
      codexBinary: json['codexBinary'] as String? ?? 'codex',
      codexVersion: json['codexVersion'] as String? ?? '',
      apiKeyConfigured: json['apiKeyConfigured'] as bool? ?? false,
      usage: json['usage'] is Map
          ? UsageOverview.fromJson(
              (json['usage'] as Map).cast<String, dynamic>(),
            )
          : UsageOverview.empty,
    );
  }

  static const fallback = ComposerContext(
    transport: 'Local',
    model: '',
    models: [],
    modelLabels: {},
    reasoningEffort: '',
    reasoningEfforts: [],
    modelReasoningEfforts: {},
    modelDefaultReasoningEfforts: {},
    approvalPolicy: 'on-request',
    requireConfirmGitWrite: true,
    branch: '',
    bridgeVersion: '',
    codexBinary: 'codex',
    codexVersion: '',
    apiKeyConfigured: false,
    usage: UsageOverview.empty,
  );

  /// Parses both the current App Server shape (`[{reasoningEffort: ...}]`)
  /// and older/string-only capability lists without adding local values.
  static List<String> parseReasoningEfforts(Object? raw) {
    if (raw is! List) return const [];
    final values = <String>[];
    for (final item in raw) {
      final value = item is Map
          ? _readNonEmptyString(
              item['reasoningEffort'] ??
                  item['reasoning_effort'] ??
                  item['effort'] ??
                  item['id'] ??
                  item['value'],
            )
          : _readNonEmptyString(item);
      if (value != null && !values.contains(value)) values.add(value);
    }
    return List.unmodifiable(values);
  }

  static String _resolveReasoningEffort({
    required String requested,
    required List<String> available,
    String? advertisedDefault,
  }) {
    if (available.isEmpty) return requested;
    if (requested.isNotEmpty && available.contains(requested)) return requested;
    if (advertisedDefault != null && available.contains(advertisedDefault)) {
      return advertisedDefault;
    }
    return available.first;
  }

  static String? _readNonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class UsageOverview {
  const UsageOverview({
    required this.todayTokens,
    required this.monthTokens,
    required this.todayCost,
    required this.monthCost,
    required this.lastUpdated,
    required this.canReadUsage,
    required this.rateConfigured,
  });

  final int todayTokens;
  final int monthTokens;
  final double todayCost;
  final double monthCost;
  final DateTime? lastUpdated;
  final bool canReadUsage;
  final bool rateConfigured;

  factory UsageOverview.fromJson(Map<String, dynamic> json) {
    return UsageOverview(
      todayTokens: _jsonInt(json['todayTokens']),
      monthTokens: _jsonInt(json['monthTokens']),
      todayCost: _jsonDouble(json['todayCost']),
      monthCost: _jsonDouble(json['monthCost']),
      lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? ''),
      canReadUsage: json['canReadUsage'] as bool? ?? false,
      rateConfigured: json['rateConfigured'] as bool? ?? false,
    );
  }

  static const empty = UsageOverview(
    todayTokens: 0,
    monthTokens: 0,
    todayCost: 0,
    monthCost: 0,
    lastUpdated: null,
    canReadUsage: false,
    rateConfigured: false,
  );
}

int _jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _jsonNullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.round();
  return int.tryParse(value.toString().trim());
}

bool _jsonBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

double _jsonDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
