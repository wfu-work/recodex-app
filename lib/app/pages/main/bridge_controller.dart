import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../models/bridge_models.dart';

class BridgeController extends GetxController {
  static const _storage = FlutterSecureStorage();

  final baseUrl = 'http://127.0.0.1:8765'.obs;
  final deviceName = 'Flutter phone'.obs;
  final deviceId = 'flutter_${DateTime.now().millisecondsSinceEpoch}'.obs;
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
  final currentSessionId = RxnString();
  final timelineSessionRunning = false.obs;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _liveTimelineTimer;
  int _messageSeq = 0;
  bool _manualDisconnect = false;
  String? _requestedEventsSessionId;
  String? _requestedEventsPrompt;
  String? _storedWorkspaceName;
  String? _storedWorkspacePath;

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
    refreshContext();
    gitStatus(includeDiff: true);
    _loadLatestSessionEventsForSelectedWorkspace();
  }

  void startSession(String prompt) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) return;
    events.add(SessionEvent(kind: 'user', text: trimmedPrompt));
    currentSessionId.value = null;
    timelineSessionRunning.value = true;
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
    _liveTimelineTimer = Timer.periodic(const Duration(milliseconds: 1200), (
      _,
    ) {
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
          _loadLatestSessionEventsForSelectedWorkspace();
        case 'session.list.result':
          sessions.assignAll(
            ((map['sessions'] as List?) ?? const []).whereType<Map>().map(
              (item) => SessionRecord.fromJson(item.cast<String, dynamic>()),
            ),
          );
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
          currentSessionId.value = record.id;
          timelineSessionRunning.value = true;
          sessions.insert(0, record);
          events.add(
            const SessionEvent(kind: 'running', text: '正在启动 Codex 任务...'),
          );
        case 'session.event':
          final event = SessionEvent.fromJson(map);
          if (!_hasDuplicateUserEvent(event)) {
            events.add(event);
          }
        case 'session.done':
          events.add(SessionEvent.fromJson(map));
          currentSessionId.value = null;
          timelineSessionRunning.value = false;
          _send('session.list', {});
          gitStatus(includeDiff: true);
        case 'session.events.result':
          final sessionId = map['sessionId'] as String? ?? '';
          if (sessionId != _requestedEventsSessionId) break;
          events.assignAll(
            _withPromptEvent(
              ((map['events'] as List?) ?? const []).whereType<Map>().map(
                (item) => SessionEvent.fromJson(item.cast<String, dynamic>()),
              ),
              _requestedEventsPrompt,
            ),
          );
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
          currentSessionId.value = null;
          timelineSessionRunning.value = false;
        case 'session.interrupted':
          currentSessionId.value = null;
          timelineSessionRunning.value = false;
          events.add(
            const SessionEvent(
              kind: 'interrupted',
              text: 'Interrupted by user.',
            ),
          );
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
    if (!canUseWorkspace) return;
    _send('session.list', {});
    if (_requestedEventsSessionId != null) {
      _send('session.events', {'sessionId': _requestedEventsSessionId});
    }
  }

  void _loadLatestSessionEventsForSelectedWorkspace({bool force = false}) {
    if (!connected.value) return;
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;

    final candidates = sessions.where(
      (session) =>
          session.workspace == workspace.path ||
          session.workspace == workspace.name,
    );
    if (candidates.isEmpty) {
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      timelineSessionRunning.value = false;
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
    currentSessionId.value = latest.status == 'running' ? latest.id : null;
    timelineSessionRunning.value = latest.status == 'running';

    if (!force && _requestedEventsSessionId == latest.id && events.isNotEmpty) {
      return;
    }

    _requestedEventsSessionId = latest.id;
    _requestedEventsPrompt = latest.prompt;
    _send('session.events', {'sessionId': latest.id});
  }

  bool _hasDuplicateUserEvent(SessionEvent event) {
    return event.kind == 'user' &&
        events.any(
          (existing) =>
              existing.kind == 'user' &&
              existing.text.trim() == event.text.trim(),
        );
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
        await _storage.write(key: 'recodex_device_id', value: deviceId.value);
      }
      if (storedDeviceKey != null && storedDeviceKey.isNotEmpty) {
        deviceKey.value = storedDeviceKey;
      }
      if (storedPairingToken != null && storedPairingToken.isNotEmpty) {
        pairingToken.value = storedPairingToken;
      }
      if (deviceKey.value.isNotEmpty || pairingToken.value.isNotEmpty) {
        unawaited(_autoConnect());
      }
    } catch (_) {
      // Tests and unsupported desktop targets may not have a secure storage backend.
    }
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
