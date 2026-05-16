import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../models/bridge_models.dart';
import '../../services/task_notification_controller.dart';

class BridgeController extends GetxController {
  static const _storage = FlutterSecureStorage();

  final baseUrl = 'http://127.0.0.1:8765'.obs;
  final deviceName = 'Flutter phone'.obs;
  final deviceId = ''.obs;
  final deviceKey = ''.obs;
  final pairingToken = ''.obs;
  final connectionLabel = 'offline'.obs;
  final lastError = ''.obs;
  final connected = false.obs;
  final busy = false.obs;

  final workspaces = <WorkspaceInfo>[].obs;
  final sessions = <SessionRecord>[].obs;
  final events = <SessionEvent>[].obs;
  final devices = <DeviceInfo>[].obs;

  final selectedWorkspace = Rxn<WorkspaceInfo>();
  final gitSnapshot = Rxn<GitSnapshot>();
  final composerContext = ComposerContext.fallback.obs;
  final permissionMode = '默认权限'.obs;
  final currentSessionId = RxnString();
  final timelineSessionRunning = false.obs;
  final timelineRevision = 0.obs;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _liveTimelineTimer;
  int _messageSeq = 0;
  bool _manualDisconnect = false;
  bool _pendingSessionStart = false;
  final _credentialsLoaded = Completer<void>();
  String? _requestedEventsSessionId;
  String? _requestedEventsPrompt;
  String? _storedWorkspaceName;
  String? _storedWorkspacePath;
  final _sessionLifecycles = <String, _SessionLifecycle>{};
  final _notifiedTerminalSessions = <String>{};

  bool get canUseWorkspace =>
      connected.value && selectedWorkspace.value != null;
  bool get hasDeviceKey => deviceKey.value.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadStoredCredentials());
  }

  @override
  void onClose() {
    stopLiveTimelineRefresh();
    unawaited(disconnect(silent: true));
    super.onClose();
  }

  Future<void> connect({
    required String inputBaseUrl,
    required String token,
    required String inputDeviceName,
  }) async {
    await _ensureCredentialsLoaded();
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    busy.value = true;
    lastError.value = '';
    connectionLabel.value = 'connecting';

    try {
      await _closeSocket();
      baseUrl.value = _normalizeBaseUrl(inputBaseUrl);
      deviceName.value = inputDeviceName.trim().isEmpty
          ? 'Flutter phone'
          : inputDeviceName.trim();
      final wsUrl = '${baseUrl.value.replaceFirst(RegExp('^http'), 'ws')}/ws';
      final trimmedToken = token.trim();
      if (trimmedToken.isNotEmpty) {
        pairingToken.value = trimmedToken;
        unawaited(
          _storage.write(key: 'recodex_pairing_token', value: trimmedToken),
        );
      }
      _socket = await WebSocket.connect(wsUrl);
      _socketSubscription = _socket!.listen(
        _handleRawMessage,
        onDone: _handleDone,
        onError: _handleSocketError,
      );
      _send('auth.hello', {
        'deviceId': deviceId.value,
        'deviceName': deviceName.value,
        'deviceKey': deviceKey.value,
        'token': trimmedToken.isNotEmpty ? trimmedToken : pairingToken.value,
      });
    } catch (error) {
      _fail(error);
      connectionLabel.value = 'failed';
      connected.value = false;
      _scheduleReconnect();
    } finally {
      busy.value = false;
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    await _closeSocket();
    connected.value = false;
    connectionLabel.value = 'offline';
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    final subscription = _socketSubscription;
    _socket = null;
    _socketSubscription = null;
    await subscription?.cancel();
    if (socket != null) {
      await socket.close();
    }
  }

  void selectWorkspace(WorkspaceInfo? workspace) {
    selectedWorkspace.value = workspace;
    unawaited(_storeSelectedWorkspace(workspace));
    gitSnapshot.value = null;
    currentSessionId.value = null;
    timelineSessionRunning.value = false;
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    events.clear();
    _bumpTimelineRevision();
    refreshContext();
    gitStatus(includeDiff: true);
    _loadLatestSessionEventsForSelectedWorkspace(force: true);
  }

  void startSession(String prompt) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) return;
    events.add(SessionEvent(kind: 'user', text: trimmedPrompt));
    _bumpTimelineRevision();
    currentSessionId.value = null;
    timelineSessionRunning.value = true;
    _pendingSessionStart = true;
    _send('session.start', {
      'workspace': workspace.name,
      'prompt': trimmedPrompt,
      'model': composerContext.value.model,
      'reasoningEffort': composerContext.value.reasoningEffort,
    });
  }

  void setComposerModel(String model) {
    composerContext.value = composerContext.value.copyWith(model: model);
  }

  void setReasoningEffort(String effort) {
    composerContext.value = composerContext.value.copyWith(
      reasoningEffort: effort,
    );
  }

  void setPermissionMode(String mode) {
    permissionMode.value = mode;
  }

  void interrupt() {
    final sessionId = currentSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return;
    _send('session.interrupt', {'sessionId': sessionId});
  }

  void gitStatus({required bool includeDiff}) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    _send(includeDiff ? 'git.diff' : 'git.status', {
      'workspace': workspace.name,
    });
  }

  void gitCommit(String message, {required bool confirm}) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    _send('git.commit', {
      'workspace': workspace.name,
      'message': message.trim(),
      'confirm': confirm,
    });
  }

  void gitPush({required bool confirm}) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    _send('git.push', {'workspace': workspace.name, 'confirm': confirm});
  }

  void gitUndo({required bool confirm}) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    _send('git.undo', {'workspace': workspace.name, 'confirm': confirm});
  }

  Future<PairingInfo?> fetchPairing(String inputBaseUrl) async {
    busy.value = true;
    lastError.value = '';
    try {
      final normalized = _normalizeBaseUrl(inputBaseUrl);
      final uri = Uri.parse('$normalized/pairing');
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(body, uri: uri);
        }
        final info = PairingInfo.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        baseUrl.value = info.baseUrl;
        if (info.token.isNotEmpty) {
          pairingToken.value = info.token;
          unawaited(_storeConnectionHints());
        }
        return info;
      } finally {
        client.close();
      }
    } catch (error) {
      _fail(error);
      return null;
    } finally {
      busy.value = false;
    }
  }

  void refreshDevices() {
    _send('device.list', {});
  }

  void refreshContext() {
    final workspace = selectedWorkspace.value;
    _send('context.get', {'workspace': workspace?.name ?? ''});
  }

  void startLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _refreshLiveTimeline();
    _liveTimelineTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      _refreshLiveTimeline();
    });
  }

  void stopLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _liveTimelineTimer = null;
  }

  void revokeDevice(String id) {
    _send('device.revoke', {'deviceId': id});
  }

  Future<void> clearStoredCredentials() async {
    deviceKey.value = '';
    pairingToken.value = '';
    lastError.value = '';
    try {
      await _storage.delete(key: 'recodex_device_key');
      await _storage.delete(key: 'recodex_pairing_token');
    } catch (_) {
      lastError.value = 'Secure storage is unavailable on this target.';
    }
  }

  void _handleRawMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = decoded['type'] as String? ?? '';
      final payload = decoded['payload'];
      final map = payload is Map<String, dynamic>
          ? payload
          : <String, dynamic>{};

      switch (type) {
        case 'bridge.hello':
          connectionLabel.value = 'auth';
        case 'auth.ok':
          connected.value = true;
          connectionLabel.value = 'online';
          final newKey = map['deviceKey'] as String? ?? '';
          if (newKey.isNotEmpty) {
            deviceKey.value = newKey;
          }
          pairingToken.value = '';
          unawaited(_storeCredentials(clearPairingToken: true));
          _send('workspace.list', {});
          _send('session.list', {});
          _send('device.list', {});
          _send('context.get', {});
        case 'workspace.list.result':
          workspaces.assignAll(
            ((map['workspaces'] as List?) ?? const []).whereType<Map>().map(
              (item) => WorkspaceInfo.fromJson(item.cast<String, dynamic>()),
            ),
          );
          selectedWorkspace.value ??= _restoreSelectedWorkspace();
          refreshContext();
          gitStatus(includeDiff: true);
          _loadLatestSessionEventsForSelectedWorkspace(force: true);
        case 'session.list.result':
          final nextSessions = ((map['sessions'] as List?) ?? const [])
              .whereType<Map>()
              .map(
                (item) => SessionRecord.fromJson(item.cast<String, dynamic>()),
              )
              .toList();
          _syncSessionCompletionNotifications(nextSessions);
          sessions.assignAll(nextSessions);
          _loadLatestSessionEventsForSelectedWorkspace(
            force: _liveTimelineTimer != null,
          );
        case 'device.list.result':
          devices.assignAll(
            ((map['devices'] as List?) ?? const []).whereType<Map>().map(
              (item) => DeviceInfo.fromJson(item.cast<String, dynamic>()),
            ),
          );
        case 'context.result':
          composerContext.value = ComposerContext.fromJson(map);
        case 'session.created':
          final record = SessionRecord.fromJson(map);
          _pendingSessionStart = false;
          currentSessionId.value = record.id;
          timelineSessionRunning.value = true;
          _markSessionRunningForNotification(record.id);
          _requestedEventsSessionId = record.id;
          _requestedEventsPrompt = record.prompt;
          sessions.insert(0, record);
          events.add(
            const SessionEvent(kind: 'running', text: '正在启动 Codex 任务...'),
          );
          _bumpTimelineRevision();
        case 'session.event':
          final event = SessionEvent.fromJson(map);
          if (!_hasDuplicateUserEvent(event)) {
            _appendSessionEvent(event);
          }
        case 'session.done':
          final event = SessionEvent.fromJson(map);
          events.add(event);
          _bumpTimelineRevision();
          final doneSessionId =
              map['sessionId'] as String? ?? currentSessionId.value;
          if (doneSessionId != null && doneSessionId.isNotEmpty) {
            _markSessionTerminal(doneSessionId);
          }
          unawaited(
            _notifySessionFinishedOnce(
              status: TaskNotificationStatus.completed,
              sessionId: doneSessionId,
            ),
          );
          currentSessionId.value = null;
          timelineSessionRunning.value = false;
          _pendingSessionStart = false;
          _send('session.list', {});
          gitStatus(includeDiff: true);
        case 'session.events.result':
          final sessionId = map['sessionId'] as String? ?? '';
          if (sessionId != _requestedEventsSessionId) break;
          final loadedEvents = _withPromptEvent(
            ((map['events'] as List?) ?? const []).whereType<Map>().map(
              (item) => SessionEvent.fromJson(item.cast<String, dynamic>()),
            ),
            _requestedEventsPrompt,
          );
          final effectiveEvents = _effectiveLoadedEventsForSession(
            sessionId: sessionId,
            loadedEvents: loadedEvents,
          );
          final shouldShowRunning = _shouldTreatLoadedSessionAsRunning(
            sessionId: sessionId,
            loadedEvents: effectiveEvents,
          );
          final displayEvents = shouldShowRunning
              ? _withSyncedRunningEvent(effectiveEvents)
              : effectiveEvents;
          final mergedEvents = _mergeLiveEvents(displayEvents);
          if (!_hasSameTimelineEvents(events, mergedEvents)) {
            events.assignAll(mergedEvents);
            _bumpTimelineRevision();
          }
          final terminalEvent = _latestTerminalEvent(effectiveEvents);
          if (terminalEvent != null) {
            unawaited(
              _notifyTerminalEventsIfNeeded(
                sessionId: sessionId,
                events: effectiveEvents,
              ),
            );
            currentSessionId.value = null;
            timelineSessionRunning.value = false;
            _pendingSessionStart = false;
          } else if (shouldShowRunning) {
            _markSessionRunningForNotification(sessionId);
            currentSessionId.value = sessionId;
            timelineSessionRunning.value = true;
          }
        case 'session.error':
          final message =
              map['message'] as String? ??
              map['text'] as String? ??
              'Unknown error';
          if (map['code'] == 'auth_failed') {
            deviceKey.value = '';
            pairingToken.value = '';
            connected.value = false;
            connectionLabel.value = 'failed';
            unawaited(_storage.delete(key: 'recodex_device_key'));
            unawaited(_storage.delete(key: 'recodex_pairing_token'));
            unawaited(_closeSocket());
          }
          lastError.value = message;
          events.add(SessionEvent(kind: 'error', text: message));
          _bumpTimelineRevision();
          final errorSessionId =
              map['sessionId'] as String? ?? currentSessionId.value;
          if (errorSessionId != null && errorSessionId.isNotEmpty) {
            _markSessionTerminal(errorSessionId);
          }
          unawaited(
            _notifySessionFinishedOnce(
              status: TaskNotificationStatus.failed,
              sessionId: errorSessionId,
              errorMessage: message,
            ),
          );
          currentSessionId.value = null;
          timelineSessionRunning.value = false;
          _pendingSessionStart = false;
        case 'session.interrupted':
          final interruptedSessionId =
              map['sessionId'] as String? ?? currentSessionId.value;
          if (interruptedSessionId != null && interruptedSessionId.isNotEmpty) {
            _markSessionTerminal(interruptedSessionId);
          }
          unawaited(
            _notifySessionFinishedOnce(
              status: TaskNotificationStatus.interrupted,
              sessionId: interruptedSessionId,
            ),
          );
          currentSessionId.value = null;
          timelineSessionRunning.value = false;
          _pendingSessionStart = false;
          events.add(
            const SessionEvent(
              kind: 'interrupted',
              text: 'Interrupted by user.',
            ),
          );
          _bumpTimelineRevision();
        case 'git.status.result':
        case 'git.diff.result':
          final snapshot = GitSnapshot.fromJson(map);
          gitSnapshot.value = snapshot;
          if (snapshot.branch.isNotEmpty) {
            composerContext.value = composerContext.value.copyWith(
              branch: snapshot.branch,
            );
          }
        case 'git.undo.result':
          gitStatus(includeDiff: true);
        case 'device.revoke.result':
          final revokedId = map['deviceId'] as String? ?? '';
          devices.removeWhere((device) => device.id == revokedId);
          if (revokedId == deviceId.value) {
            deviceKey.value = '';
            connectionLabel.value = 'revoked';
            unawaited(disconnect());
          }
        case 'confirm.required':
          lastError.value =
              map['message'] as String? ?? 'Confirmation required.';
        default:
          break;
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _handleDone() {
    connected.value = false;
    connectionLabel.value = 'offline';
    _socket = null;
    _socketSubscription = null;
    _scheduleReconnect();
  }

  void _handleSocketError(Object error) {
    connected.value = false;
    connectionLabel.value = 'failed';
    _fail(error);
    _scheduleReconnect();
  }

  void _send(String type, Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    _messageSeq += 1;
    socket.add(
      jsonEncode({'type': type, 'id': 'm_$_messageSeq', 'payload': payload}),
    );
  }

  void _refreshLiveTimeline() {
    if (!connected.value) return;
    _send('session.list', {});
    if (_requestedEventsSessionId != null) {
      _send('session.events', {'sessionId': _requestedEventsSessionId});
    }
  }

  void _syncSessionCompletionNotifications(List<SessionRecord> nextSessions) {
    for (final session in nextSessions) {
      final status = session.status.toLowerCase();
      if (status == 'running') {
        _markSessionRunningForNotification(session.id);
        continue;
      }
      if (!_isTerminalSessionStatus(status)) {
        continue;
      }
      final wasRunning =
          _shouldNotifyTerminalSession(session.id) ||
          session.id == currentSessionId.value && timelineSessionRunning.value;
      if (!wasRunning) {
        continue;
      }
      _markSessionTerminal(session.id);
      unawaited(
        _notifySessionFinishedOnce(
          status: _notificationStatusForSessionStatus(status),
          sessionId: session.id,
          notificationKey: _notificationKeyForSession(session),
          workspaceName: _workspaceNameForSession(session.workspace),
          prompt: session.prompt,
        ),
      );
    }
  }

  void _markSessionRunningForNotification(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return;
    final lifecycle = _sessionLifecycle(sessionId);
    lifecycle.observedRunning = true;
    lifecycle.visibleRunning = true;
    lifecycle.terminalObserved = false;
  }

  bool _shouldNotifyTerminalSession(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return false;
    final lifecycle = _sessionLifecycles[sessionId];
    if (lifecycle == null || lifecycle.terminalObserved) return false;
    return lifecycle.observedRunning || lifecycle.visibleRunning;
  }

  void _markSessionTerminal(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return;
    final lifecycle = _sessionLifecycle(sessionId);
    lifecycle.terminalObserved = true;
    lifecycle.observedRunning = false;
    lifecycle.visibleRunning = false;
  }

  _SessionLifecycle _sessionLifecycle(String sessionId) {
    return _sessionLifecycles.putIfAbsent(sessionId, _SessionLifecycle.new);
  }

  String _notificationKeyForSession(SessionRecord session) {
    final updatedAt = session.updatedAt.trim();
    if (updatedAt.isEmpty) return session.id;
    return '${session.id}:$updatedAt';
  }

  bool _isTerminalSessionStatus(String status) {
    return status == 'done' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'error' ||
        status == 'failed' ||
        status == 'interrupted';
  }

  TaskNotificationStatus _notificationStatusForSessionStatus(String status) {
    return switch (status) {
      'error' || 'failed' => TaskNotificationStatus.failed,
      'interrupted' => TaskNotificationStatus.interrupted,
      _ => TaskNotificationStatus.completed,
    };
  }

  String _workspaceNameForSession(String workspace) {
    final normalized = _normalizeWorkspaceKey(workspace);
    for (final item in workspaces) {
      if (_normalizeWorkspaceKey(item.path) == normalized ||
          _normalizeWorkspaceKey(item.name) == normalized) {
        return item.name.isNotEmpty ? item.name : item.path;
      }
    }
    return _lastPathSegment(normalized);
  }

  void _loadLatestSessionEventsForSelectedWorkspace({bool force = false}) {
    if (!connected.value) return;
    if (_pendingSessionStart) return;
    if (sessions.isEmpty) {
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      timelineSessionRunning.value = false;
      if (events.isNotEmpty) {
        events.clear();
        _bumpTimelineRevision();
      }
      return;
    }

    final workspace = selectedWorkspace.value;
    final candidates = _timelineSessionCandidates(workspace);
    if (candidates.isEmpty) {
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      timelineSessionRunning.value = false;
      if (events.isNotEmpty) {
        events.clear();
        _bumpTimelineRevision();
      }
      return;
    }

    final runningCandidates = candidates.where(
      (session) => session.status == 'running',
    );
    final timelineCandidates = runningCandidates.isEmpty
        ? candidates
        : runningCandidates;
    final latest = timelineCandidates.reduce(
      (current, next) =>
          next.updatedAtDate.isAfter(current.updatedAtDate) ? next : current,
    );
    final requestedRunning =
        _requestedEventsSessionId == latest.id && timelineSessionRunning.value;
    if (latest.status == 'running') {
      _markSessionRunningForNotification(latest.id);
      currentSessionId.value = latest.id;
      timelineSessionRunning.value = true;
    } else if (!requestedRunning) {
      currentSessionId.value = null;
      timelineSessionRunning.value = false;
    }

    if (!force && _requestedEventsSessionId == latest.id && events.isNotEmpty) {
      return;
    }

    _requestedEventsSessionId = latest.id;
    _requestedEventsPrompt = latest.prompt;
    _send('session.events', {'sessionId': latest.id});
  }

  List<SessionRecord> _timelineSessionCandidates(WorkspaceInfo? workspace) {
    if (workspace == null) return List<SessionRecord>.of(sessions);
    final workspaceName = _normalizeWorkspaceKey(workspace.name);
    final workspacePath = _normalizeWorkspaceKey(workspace.path);
    final strictMatches = sessions
        .where(
          (session) => _workspaceMatchesSession(
            session.workspace,
            workspaceName,
            workspacePath,
            allowBasename: false,
          ),
        )
        .toList();
    if (strictMatches.isNotEmpty) return strictMatches;

    return sessions.where((session) {
      return _workspaceMatchesSession(
        session.workspace,
        workspaceName,
        workspacePath,
        allowBasename: true,
      );
    }).toList();
  }

  bool _hasDuplicateUserEvent(SessionEvent event) {
    return event.kind == 'user' &&
        events.any(
          (existing) =>
              existing.kind == 'user' &&
              existing.text.trim() == event.text.trim(),
        );
  }

  void _appendSessionEvent(SessionEvent event) {
    if (event.kind == 'running') {
      final last = events.isEmpty ? null : events.last;
      if (last?.kind == 'running') {
        events[events.length - 1] = event;
        _bumpTimelineRevision();
        return;
      }
    }
    events.add(event);
    _bumpTimelineRevision();
  }

  void _bumpTimelineRevision() {
    timelineRevision.value += 1;
  }

  String _normalizeWorkspaceKey(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _workspaceMatchesSession(
    String sessionWorkspace,
    String workspaceName,
    String workspacePath, {
    required bool allowBasename,
  }) {
    final session = _normalizeWorkspaceKey(sessionWorkspace);
    if (session.isEmpty) return false;
    if (workspacePath.isNotEmpty && session == workspacePath) return true;
    if (workspaceName.isNotEmpty && session == workspaceName) return true;
    if (workspaceName.isNotEmpty && session.endsWith('/$workspaceName')) {
      return true;
    }
    if (!allowBasename) return false;
    final sessionName = _lastPathSegment(session);
    final pathName = _lastPathSegment(workspacePath);
    return workspaceName.isNotEmpty && sessionName == workspaceName ||
        pathName.isNotEmpty && sessionName == pathName;
  }

  String _lastPathSegment(String value) {
    final normalized = _normalizeWorkspaceKey(value);
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? normalized : parts.last;
  }

  List<SessionEvent> _mergeLiveEvents(List<SessionEvent> loadedEvents) {
    if (!timelineSessionRunning.value || events.isEmpty) return loadedEvents;
    final merged = List<SessionEvent>.of(loadedEvents);
    for (final event in events) {
      if (!_isLiveStatusEvent(event) || _containsSimilarEvent(merged, event)) {
        continue;
      }
      merged.add(event);
    }
    return merged;
  }

  List<SessionEvent> _effectiveLoadedEventsForSession({
    required String sessionId,
    required List<SessionEvent> loadedEvents,
  }) {
    final record = _sessionById(sessionId);
    if (record?.status != 'running') {
      return loadedEvents;
    }
    return _withoutStaleTerminalEventsAfterLastUser(loadedEvents);
  }

  List<SessionEvent> _withoutStaleTerminalEventsAfterLastUser(
    List<SessionEvent> source,
  ) {
    var lastUserIndex = -1;
    for (var index = 0; index < source.length; index += 1) {
      if (source[index].kind == 'user') {
        lastUserIndex = index;
      }
    }
    if (lastUserIndex < 0) {
      return source;
    }
    final next = <SessionEvent>[];
    var hasAnswerAfterLastUser = false;
    for (var index = 0; index < source.length; index += 1) {
      final event = source[index];
      final afterLastUser = index > lastUserIndex;
      if (afterLastUser &&
          _isTerminalEventKind(event.kind) &&
          !hasAnswerAfterLastUser) {
        continue;
      }
      if (afterLastUser &&
          (event.kind == 'assistant' ||
              event.kind == 'git_change' ||
              event.kind == 'tool_call')) {
        hasAnswerAfterLastUser = true;
      }
      next.add(event);
    }
    return next;
  }

  bool _shouldTreatLoadedSessionAsRunning({
    required String sessionId,
    required List<SessionEvent> loadedEvents,
  }) {
    final record = _sessionById(sessionId);
    if (record?.status == 'running' &&
        _latestMeaningfulEventIsUser(loadedEvents)) {
      return true;
    }
    if (_latestTerminalEvent(loadedEvents) != null) return false;
    if (record == null) {
      return sessionId == currentSessionId.value &&
          timelineSessionRunning.value;
    }
    if (record.status == 'running') return true;
    return false;
  }

  bool _latestMeaningfulEventIsUser(List<SessionEvent> source) {
    for (final event in source.reversed) {
      if (event.kind == 'token_usage') continue;
      if (_isLiveStatusEvent(event)) continue;
      return event.kind == 'user';
    }
    return false;
  }

  List<SessionEvent> _withSyncedRunningEvent(List<SessionEvent> source) {
    if (source.isNotEmpty && _isLiveStatusEvent(source.last)) {
      return source;
    }
    return [
      ...source,
      const SessionEvent(kind: 'running', text: '正在同步电脑端 Codex 执行...'),
    ];
  }

  SessionRecord? _sessionById(String sessionId) {
    for (final session in sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  bool _isLiveStatusEvent(SessionEvent event) {
    return event.kind == 'running' || event.kind == 'tool_call';
  }

  bool _isTerminalEventKind(String kind) {
    final normalized = kind.toLowerCase();
    return normalized == 'done' ||
        normalized == 'interrupted' ||
        normalized == 'error' ||
        normalized.contains('complete') ||
        normalized.contains('completed');
  }

  bool _containsSimilarEvent(List<SessionEvent> source, SessionEvent event) {
    return source.any(
      (candidate) =>
          candidate.kind == event.kind &&
          candidate.text.trim() == event.text.trim(),
    );
  }

  bool _hasSameTimelineEvents(
    List<SessionEvent> current,
    List<SessionEvent> next,
  ) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index += 1) {
      final a = current[index];
      final b = next[index];
      if (a.kind != b.kind ||
          a.text != b.text ||
          a.attachments.length != b.attachments.length) {
        return false;
      }
      for (
        var attachmentIndex = 0;
        attachmentIndex < a.attachments.length;
        attachmentIndex += 1
      ) {
        if (a.attachments[attachmentIndex].dataUrl !=
            b.attachments[attachmentIndex].dataUrl) {
          return false;
        }
      }
    }
    return true;
  }

  SessionEvent? _latestTerminalEvent(List<SessionEvent> source) {
    for (final event in source.reversed) {
      final kind = event.kind.toLowerCase();
      if (kind == 'token_usage') continue;
      if (kind == 'running' || kind == 'tool_call') return null;
      if (kind == 'user' || kind == 'assistant' || kind == 'git_change') {
        return null;
      }
      if (kind == 'done' ||
          kind == 'interrupted' ||
          kind == 'error' ||
          kind.contains('complete') ||
          kind.contains('completed')) {
        return event;
      }
      if (event.text.trim().isNotEmpty) return null;
    }
    return null;
  }

  Future<void> _notifyTerminalEventsIfNeeded({
    required String sessionId,
    required List<SessionEvent> events,
  }) async {
    if (sessionId.isEmpty) return;
    final terminal = _latestTerminalEvent(events);
    if (terminal == null) return;
    _markSessionTerminal(sessionId);
    final kind = terminal.kind.toLowerCase();
    final status = kind == 'error'
        ? TaskNotificationStatus.failed
        : kind == 'interrupted'
        ? TaskNotificationStatus.interrupted
        : TaskNotificationStatus.completed;
    await _notifySessionFinishedOnce(
      status: status,
      sessionId: sessionId,
      notificationKey: _notificationKeyForTerminalEvent(sessionId, terminal),
      errorMessage: status == TaskNotificationStatus.failed
          ? terminal.text
          : null,
    );
  }

  Future<void> _notifySessionFinishedOnce({
    required TaskNotificationStatus status,
    required String? sessionId,
    String? notificationKey,
    String? workspaceName,
    String? prompt,
    String? errorMessage,
  }) async {
    final dedupeKey = notificationKey ?? sessionId;
    if (dedupeKey != null &&
        dedupeKey.isNotEmpty &&
        !_notifiedTerminalSessions.add(dedupeKey)) {
      return;
    }
    await _notifySessionFinished(
      status: status,
      sessionId: sessionId,
      workspaceName: workspaceName,
      prompt: prompt,
      errorMessage: errorMessage,
    );
  }

  String _notificationKeyForTerminalEvent(
    String sessionId,
    SessionEvent terminal,
  ) {
    final timeKey = terminal.time?.toIso8601String() ?? '';
    if (timeKey.isNotEmpty) return '$sessionId:$timeKey';
    final promptKey = _currentPrompt();
    if (promptKey.isNotEmpty) return '$sessionId:$promptKey';
    return sessionId;
  }

  Future<void> _notifySessionFinished({
    required TaskNotificationStatus status,
    required String? sessionId,
    String? workspaceName,
    String? prompt,
    String? errorMessage,
  }) async {
    if (!Get.isRegistered<TaskNotificationController>()) return;
    final workspace = selectedWorkspace.value;
    await Get.find<TaskNotificationController>().notifySessionTerminal(
      status: status,
      sessionId: sessionId,
      workspaceName: workspaceName ?? workspace?.name ?? workspace?.path ?? '',
      prompt: prompt ?? _currentPrompt(),
      errorMessage: errorMessage,
    );
  }

  String _currentPrompt() {
    if ((_requestedEventsPrompt ?? '').trim().isNotEmpty) {
      return _requestedEventsPrompt!.trim();
    }
    for (final event in events.reversed) {
      if (event.kind == 'user' && event.text.trim().isNotEmpty) {
        return event.text.trim();
      }
    }
    return '';
  }

  List<SessionEvent> _withPromptEvent(
    Iterable<SessionEvent> source,
    String? prompt,
  ) {
    final loadedEvents = source.toList();
    final trimmedPrompt = prompt?.trim() ?? '';
    if (trimmedPrompt.isEmpty ||
        loadedEvents.any((event) => event.kind == 'user')) {
      return loadedEvents;
    }
    return [SessionEvent(kind: 'user', text: trimmedPrompt), ...loadedEvents];
  }

  Future<void> _loadStoredCredentials() async {
    var shouldAutoConnect = false;
    try {
      final storedBaseUrl = await _storage.read(key: 'recodex_base_url');
      final storedDeviceName = await _storage.read(key: 'recodex_device_name');
      final storedDeviceId = await _storage.read(key: 'recodex_device_id');
      final storedDeviceKey = await _storage.read(key: 'recodex_device_key');
      final storedPairingToken = await _storage.read(
        key: 'recodex_pairing_token',
      );
      _storedWorkspaceName = await _storage.read(
        key: 'recodex_selected_workspace_name',
      );
      _storedWorkspacePath = await _storage.read(
        key: 'recodex_selected_workspace_path',
      );
      if (storedBaseUrl != null && storedBaseUrl.isNotEmpty) {
        baseUrl.value = _normalizeBaseUrl(storedBaseUrl);
      }
      if (storedDeviceName != null && storedDeviceName.isNotEmpty) {
        deviceName.value = storedDeviceName;
      }
      if (storedDeviceId != null && storedDeviceId.isNotEmpty) {
        deviceId.value = storedDeviceId;
      } else {
        deviceId.value = _newDeviceId();
        await _storage.write(key: 'recodex_device_id', value: deviceId.value);
      }
      if (storedDeviceKey != null && storedDeviceKey.isNotEmpty) {
        deviceKey.value = storedDeviceKey;
      }
      if (storedPairingToken != null && storedPairingToken.isNotEmpty) {
        pairingToken.value = storedPairingToken;
      }
      shouldAutoConnect =
          deviceKey.value.isNotEmpty || pairingToken.value.isNotEmpty;
    } catch (_) {
      // Tests and unsupported desktop targets may not have a secure storage backend.
      if (deviceId.value.isEmpty) {
        deviceId.value = _newDeviceId();
      }
    } finally {
      if (!_credentialsLoaded.isCompleted) {
        _credentialsLoaded.complete();
      }
    }

    if (shouldAutoConnect) {
      unawaited(_autoConnect());
    }
  }

  Future<void> _ensureCredentialsLoaded() async {
    if (!_credentialsLoaded.isCompleted) {
      await _credentialsLoaded.future;
    }
    if (deviceId.value.isEmpty) {
      deviceId.value = _newDeviceId();
    }
  }

  String _newDeviceId() {
    return 'flutter_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _storeConnectionHints() async {
    try {
      await _storage.write(key: 'recodex_base_url', value: baseUrl.value);
      await _storage.write(key: 'recodex_device_name', value: deviceName.value);
      await _storage.write(key: 'recodex_device_id', value: deviceId.value);
      if (pairingToken.value.isNotEmpty) {
        await _storage.write(
          key: 'recodex_pairing_token',
          value: pairingToken.value,
        );
      }
    } catch (_) {
      // Keep the in-memory values for the current connection if storage is unavailable.
    }
  }

  Future<void> _storeCredentials({bool clearPairingToken = false}) async {
    try {
      await _storeConnectionHints();
      await _storage.write(key: 'recodex_device_key', value: deviceKey.value);
      if (clearPairingToken) {
        await _storage.delete(key: 'recodex_pairing_token');
      }
    } catch (_) {
      // Keep the in-memory key for the current connection if secure storage is unavailable.
    }
  }

  WorkspaceInfo? _restoreSelectedWorkspace() {
    if (workspaces.isEmpty) return null;
    final storedName = _storedWorkspaceName?.trim() ?? '';
    final storedPath = _storedWorkspacePath?.trim() ?? '';
    for (final workspace in workspaces) {
      if (storedPath.isNotEmpty && workspace.path == storedPath) {
        return workspace;
      }
      if (storedName.isNotEmpty && workspace.name == storedName) {
        return workspace;
      }
    }
    return workspaces.first;
  }

  Future<void> _storeSelectedWorkspace(WorkspaceInfo? workspace) async {
    try {
      if (workspace == null) {
        _storedWorkspaceName = null;
        _storedWorkspacePath = null;
        await _storage.delete(key: 'recodex_selected_workspace_name');
        await _storage.delete(key: 'recodex_selected_workspace_path');
        return;
      }
      _storedWorkspaceName = workspace.name;
      _storedWorkspacePath = workspace.path;
      await _storage.write(
        key: 'recodex_selected_workspace_name',
        value: workspace.name,
      );
      await _storage.write(
        key: 'recodex_selected_workspace_path',
        value: workspace.path,
      );
    } catch (_) {
      // Keep the in-memory selection for this run if secure storage is unavailable.
    }
  }

  Future<void> _autoConnect() {
    return connect(
      inputBaseUrl: baseUrl.value,
      token: pairingToken.value,
      inputDeviceName: deviceName.value,
    );
  }

  void _scheduleReconnect() {
    if (_manualDisconnect ||
        (deviceKey.value.isEmpty && pairingToken.value.isEmpty) ||
        _reconnectTimer != null) {
      return;
    }
    connectionLabel.value = 'reconnecting';
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      if (!_manualDisconnect &&
          !connected.value &&
          (deviceKey.value.isNotEmpty || pairingToken.value.isNotEmpty)) {
        unawaited(_autoConnect());
      }
    });
  }

  void _fail(Object error) {
    lastError.value = error.toString();
  }

  String _normalizeBaseUrl(String value) {
    var next = value.trim();
    if (next.isEmpty) next = 'http://127.0.0.1:8765';
    if (!next.startsWith('http://') && !next.startsWith('https://')) {
      next = 'http://$next';
    }
    while (next.endsWith('/')) {
      next = next.substring(0, next.length - 1);
    }
    return next;
  }
}

class _SessionLifecycle {
  bool observedRunning = false;
  bool visibleRunning = false;
  bool terminalObserved = false;
}
