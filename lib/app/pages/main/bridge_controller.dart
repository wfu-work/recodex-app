import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../models/bridge_models.dart';
import '../../services/relay_protocol.dart';
import '../../services/task_notification_controller.dart';

class BridgeController extends GetxController {
  static const _storage = FlutterSecureStorage();

  final baseUrl = 'ws://127.0.0.1:8788/v1/connect'.obs;
  final spaceId = ''.obs;
  final deviceName = 'Flutter phone'.obs;
  final deviceId = ''.obs;
  final targetDeviceId = ''.obs;
  final endpointType = 'app'.obs;
  final deviceKey = ''.obs;
  final endpointPublicKey = ''.obs;
  final pairingToken = ''.obs;
  final endpointGrant = ''.obs;
  final tokenExpiresAt = 0.obs;
  final grantExpiresAt = 0.obs;
  final relaySessionId = ''.obs;
  final connectionLabel = 'offline'.obs;
  final lastError = ''.obs;
  final connected = false.obs;
  final busy = false.obs;

  final workspaces = <WorkspaceInfo>[].obs;
  final sessions = <SessionRecord>[].obs;
  final events = <SessionEvent>[].obs;
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
  Timer? _handshakeTimer;
  Timer? _heartbeatTimer;
  int _outgoingSequence = 0;
  int _lastIncomingSequence = 0;
  int _maxFrameSize = RelayProtocol.defaultMaxFrameSize;
  bool _manualDisconnect = false;
  bool _pendingSessionStart = false;
  String? _pendingPrompt;
  String? _currentTurnId;
  String? _pendingHelloRequestId;
  SimpleKeyPair? _keyPair;
  bool _forceTokenRefresh = false;
  final _pendingCommands = <String, _PendingCommand>{};
  final _seenIncomingMessageIds = <String>{};
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
    String? inputSpaceId,
    String? inputTargetDeviceId,
    String? inputEndpointId,
    String? inputEndpointType,
    String? inputEndpointGrant,
  }) async {
    await _ensureCredentialsLoaded();
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    busy.value = true;
    lastError.value = '';
    connectionLabel.value = 'connecting';

    try {
      await _closeSocket();
      final normalizedBaseUrl = _normalizeRelayUrl(inputBaseUrl);
      final nextSpaceId = inputSpaceId == null
          ? spaceId.value
          : inputSpaceId.trim();
      final nextTargetDeviceId = inputTargetDeviceId == null
          ? targetDeviceId.value
          : inputTargetDeviceId.trim();
      final nextEndpointId = inputEndpointId == null
          ? deviceId.value
          : inputEndpointId.trim();
      final nextEndpointType = inputEndpointType == null
          ? endpointType.value
          : inputEndpointType.trim();
      final identityChanged =
          nextSpaceId != spaceId.value ||
          nextEndpointId != deviceId.value ||
          nextEndpointType != endpointType.value;
      final sessionChanged =
          normalizedBaseUrl != baseUrl.value ||
          identityChanged ||
          nextTargetDeviceId != targetDeviceId.value;
      final previousToken = pairingToken.value;
      final previousGrant = endpointGrant.value;
      baseUrl.value = normalizedBaseUrl;
      spaceId.value = nextSpaceId;
      targetDeviceId.value = nextTargetDeviceId;
      deviceId.value = nextEndpointId;
      endpointType.value = nextEndpointType;
      if (identityChanged) {
        pairingToken.value = '';
        endpointGrant.value = '';
        tokenExpiresAt.value = 0;
        grantExpiresAt.value = 0;
        _forceTokenRefresh = false;
      }
      if (sessionChanged) {
        relaySessionId.value = '';
        _lastIncomingSequence = 0;
        _seenIncomingMessageIds.clear();
      }
      deviceName.value = inputDeviceName.trim().isEmpty
          ? 'Flutter phone'
          : inputDeviceName.trim();
      final trimmedToken = token.trim();
      if (trimmedToken.isNotEmpty) {
        if (trimmedToken != previousToken) {
          tokenExpiresAt.value = 0;
          _forceTokenRefresh = false;
        }
        pairingToken.value = trimmedToken;
      }
      if (inputEndpointGrant != null) {
        if (inputEndpointGrant.trim() != previousGrant) {
          grantExpiresAt.value = 0;
        }
        endpointGrant.value = inputEndpointGrant.trim();
      }
      if (spaceId.value.isEmpty ||
          targetDeviceId.value.isEmpty ||
          deviceId.value.isEmpty ||
          (pairingToken.value.isEmpty && endpointGrant.value.isEmpty)) {
        throw StateError(
          'Relay 配置不完整：需要 Relay URL、Space ID、App Endpoint ID、目标 Bridge ID，以及 Connect Token 或 Endpoint Grant',
        );
      }
      _keyPair ??= await _loadOrCreateKeyPair();
      endpointPublicKey.value = await RelayProtocol.publicKey(_keyPair!);
      final connectToken = await _usableConnectToken(trimmedToken);
      _socket = await WebSocket.connect(baseUrl.value);
      _socketSubscription = _socket!.listen(
        _handleRawMessage,
        onDone: _handleDone,
        onError: _handleSocketError,
      );
      final hello = await RelayProtocol.connectHello(
        keyPair: _keyPair!,
        spaceId: spaceId.value,
        endpointId: deviceId.value,
        endpointType: endpointType.value,
        endpointName: deviceName.value,
        token: connectToken,
        resume: relaySessionId.value.isEmpty
            ? null
            : {
                'sessionId': relaySessionId.value,
                'lastAck': _lastIncomingSequence,
              },
      );
      _pendingHelloRequestId = hello['requestId'] as String?;
      _socket!.add(jsonEncode(hello));
      connectionLabel.value = 'auth';
      _handshakeTimer?.cancel();
      _handshakeTimer = Timer(const Duration(seconds: 10), () {
        if (!connected.value && connectionLabel.value == 'auth') {
          _fail(StateError('Relay 认证超时'));
          unawaited(_closeSocket());
          _scheduleReconnect();
        }
      });
      unawaited(_storeConnectionHints());
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
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _closeSocket();
    connected.value = false;
    connectionLabel.value = 'offline';
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    final subscription = _socketSubscription;
    _socket = null;
    _socketSubscription = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    _pendingPrompt = trimmedPrompt;
    _sendCommand('thread.create', {
      if (workspace.path.trim().isNotEmpty) 'cwd': workspace.path,
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
    final turnId = _currentTurnId;
    if (turnId == null || turnId.isEmpty) return;
    _sendCommand('turn.interrupt', {}, threadId: sessionId, turnId: turnId);
  }

  void gitStatus({required bool includeDiff}) {
    // Git is not part of Codex Relay Protocol v1. It is intentionally not
    // sent as an unknown product command to the plugin.
    gitSnapshot.value = null;
  }

  void gitCommit(String message, {required bool confirm}) {
    lastError.value = 'Protocol v1 当前只提供 Codex 会话命令，Git 写操作尚未开放。';
  }

  void gitPush({required bool confirm}) {
    lastError.value = 'Protocol v1 当前只提供 Codex 会话命令，Git 写操作尚未开放。';
  }

  void gitUndo({required bool confirm}) {
    lastError.value = 'Protocol v1 当前只提供 Codex 会话命令，Git 写操作尚未开放。';
  }

  void refreshContext() {
    _sendCommand('host.get_status', {});
  }

  void startLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _refreshLiveTimeline();
    _liveTimelineTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshLiveTimeline();
    });
  }

  void stopLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _liveTimelineTimer = null;
  }

  Future<void> clearStoredCredentials() async {
    await disconnect(silent: true);
    deviceKey.value = '';
    endpointPublicKey.value = '';
    _keyPair = null;
    _forceTokenRefresh = false;
    deviceId.value = _newDeviceId();
    pairingToken.value = '';
    endpointGrant.value = '';
    tokenExpiresAt.value = 0;
    grantExpiresAt.value = 0;
    lastError.value = '';
    try {
      await _storage.delete(key: 'recodex_endpoint_private_key');
      await _storage.delete(key: 'recodex_device_key');
      await _storage.delete(key: 'recodex_device_id');
      await _storage.delete(key: 'recodex_pairing_token');
      await _storage.delete(key: 'recodex_endpoint_grant');
      await _storage.delete(key: 'recodex_token_expires_at');
      await _storage.delete(key: 'recodex_grant_expires_at');
    } catch (_) {
      lastError.value = 'Secure storage is unavailable on this target.';
    }
  }

  void _handleRawMessage(dynamic raw) {
    try {
      final decoded = _decodeTextMessage(raw);
      final type = decoded['type'] as String? ?? '';
      if (type == 'connect.welcome') {
        _handleWelcome(decoded);
        return;
      }
      if (type == 'relay.error') {
        _handleRelayError(decoded);
        return;
      }
      if (type == 'stream.ack') return;
      if (type != 'stream.message') return;
      final messageId = _readString(decoded['messageId']);
      if (messageId != null && !_rememberIncomingMessage(messageId)) return;
      final sequence = decoded['sequence'];
      if (sequence is num && sequence.toInt() > _lastIncomingSequence) {
        _lastIncomingSequence = sequence.toInt();
        final from = decoded['from'] as String? ?? targetDeviceId.value;
        if (from.isNotEmpty) {
          _sendRaw(
            RelayProtocol.ack(
              stream: decoded['streamId'] as String? ?? RelayProtocol.streamId,
              sequence: _lastIncomingSequence,
              targetDeviceId: from,
            ),
          );
        }
      }
      final productMessage = RelayProtocol.unwrapProductMessage(decoded);
      if (productMessage == null) return;
      final productType = productMessage['type'] as String? ?? '';
      if (productType == 'codex.command.result') {
        _handleCommandResult(productMessage);
      } else if (productType == 'codex.event') {
        _handleCodexEvent(productMessage);
      } else if (productType == 'host.snapshot') {
        _applyHostStatus(productMessage['status']);
      }
    } catch (error) {
      _fail(error);
    }
  }

  Map<String, dynamic> _decodeTextMessage(dynamic raw) {
    if (raw is! String) throw FormatException('Relay 只接受 JSON 文本帧');
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw FormatException('Relay 帧必须是 JSON 对象');
    return RelayProtocol.validateFrame(Map<String, dynamic>.from(decoded));
  }

  void _handleWelcome(Map<String, dynamic> message) {
    RelayProtocol.validateWelcome(message);
    final requestId = _readString(message['requestId']);
    if (requestId != null && requestId != _pendingHelloRequestId) {
      throw StateError('Relay welcome requestId 与当前握手不一致');
    }
    if (message['spaceId'] != spaceId.value ||
        message['endpointId'] != deviceId.value ||
        (message['connectionId'] as String? ?? '').isEmpty) {
      throw StateError('Relay welcome 与当前 Endpoint 配置不一致');
    }
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _startHeartbeat();
    _maxFrameSize = (message['maxFrameSize'] as num).toInt();
    relaySessionId.value = message['sessionId'] as String? ?? '';
    connected.value = true;
    connectionLabel.value = 'online';
    lastError.value = '';
    _pendingCommands.clear();
    unawaited(_storeConnectionHints());
    _sendCommand('sync.request', {
      if (_lastIncomingSequence > 0) 'lastSequence': _lastIncomingSequence,
    });
    _sendCommand('thread.list', {'limit': 100});
    _sendCommand('host.get_status', {});
  }

  void _handleRelayError(Map<String, dynamic> message) {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final code = message['code'] as String? ?? 'relay.error';
    final text = message['message'] as String? ?? 'Relay 连接被拒绝';
    lastError.value = '$code：$text';
    connected.value = false;
    connectionLabel.value = 'failed';
    if (code == 'auth.token_expired' && endpointGrant.value.isNotEmpty) {
      _forceTokenRefresh = true;
      _scheduleReconnect();
      return;
    }
    if (code.startsWith('auth.') || code == 'connection.revoked') {
      pairingToken.value = '';
      endpointGrant.value = '';
      tokenExpiresAt.value = 0;
      grantExpiresAt.value = 0;
      _forceTokenRefresh = false;
      unawaited(_storage.delete(key: 'recodex_pairing_token'));
      unawaited(_storage.delete(key: 'recodex_endpoint_grant'));
    }
  }

  void _handleCommandResult(Map<String, dynamic> message) {
    final requestId = message['requestId'] as String? ?? '';
    final pending = _pendingCommands.remove(requestId);
    final success = message['success'] == true;
    if (!success) {
      final error = message['error'];
      final errorMap = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      final text = errorMap['message'] as String? ?? '远程命令执行失败';
      lastError.value = '${errorMap['code'] ?? 'remote.error'}：$text';
      if (pending?.kind == 'thread.create' || pending?.kind == 'turn.start') {
        _finishCurrentSession(
          status: TaskNotificationStatus.failed,
          message: text,
        );
      }
      return;
    }
    final result = message['result'];
    switch (pending?.kind) {
      case 'sync.request':
        _applySyncResult(result);
      case 'thread.list':
        _applyThreadListResult(result);
      case 'thread.create':
        _handleThreadCreated(result);
      case 'thread.read':
        _handleThreadReadResult(result);
      case 'turn.start':
        final map = _asMap(result);
        _currentTurnId =
            _readString(map?['turnId']) ??
            _readString(_asMap(map?['turn'])?['id']);
      case 'turn.interrupt':
        _finishCurrentSession(
          status: TaskNotificationStatus.interrupted,
          message: '已中断当前 Codex 任务。',
        );
      case 'host.get_status':
        _applyHostStatus(result);
      default:
        break;
    }
  }

  void _applySyncResult(Object? value) {
    final map = _asMap(value);
    if (map == null) return;
    final mode = _readString(map['mode']);
    if (mode == 'events') {
      for (final item in _asList(map['events'])) {
        final frame = _asMap(item);
        if (frame != null) {
          _acceptIncomingSequence(frame['sequence']);
          _handleCodexEvent(frame);
        }
      }
      _acceptIncomingSequence(map['latestSequence']);
    } else {
      _applyThreadListResult(map['threads']);
      _applyHostStatus(map['status']);
    }
  }

  void _applyThreadListResult(Object? value) {
    final map = _asMap(value);
    final rawThreads = map == null ? value : (map['data'] ?? map['threads']);
    final next = _asList(
      rawThreads,
    ).map(_sessionFromThread).whereType<SessionRecord>().toList();
    _syncSessionCompletionNotifications(next);
    sessions.assignAll(next);
    _deriveWorkspaces(next);
    selectedWorkspace.value ??= _restoreSelectedWorkspace();
    selectedWorkspace.value ??= _defaultWorkspace();
    _loadLatestSessionEventsForSelectedWorkspace(force: true);
  }

  void _deriveWorkspaces(List<SessionRecord> records) {
    final byPath = <String, WorkspaceInfo>{};
    for (final record in records) {
      final path = record.workspace.trim();
      if (path.isEmpty) continue;
      byPath[path] = WorkspaceInfo(name: _lastPathSegment(path), path: path);
    }
    if (byPath.isNotEmpty) workspaces.assignAll(byPath.values);
  }

  WorkspaceInfo _defaultWorkspace() {
    final workspace = WorkspaceInfo(name: '默认工作区', path: '');
    if (workspaces.isEmpty) workspaces.add(workspace);
    return workspace;
  }

  SessionRecord? _sessionFromThread(Object? value) {
    final map = _asMap(value);
    if (map == null) return null;
    final thread = _asMap(map['thread']) ?? map;
    final id = _readString(thread['id']);
    if (id == null || id.isEmpty) return null;
    final cwd =
        _readString(thread['cwd']) ??
        _readString(thread['workingDirectory']) ??
        '';
    final prompt =
        _readString(thread['preview']) ??
        _readString(thread['name']) ??
        _readString(thread['title']) ??
        '';
    final status = _threadStatus(thread);
    final created = _dateString(thread['createdAt'] ?? thread['created_at']);
    final updated = _dateString(thread['updatedAt'] ?? thread['updated_at']);
    return SessionRecord(
      id: id,
      workspace: cwd,
      prompt: prompt,
      status: status,
      createdAt: created,
      updatedAt: updated.isEmpty ? created : updated,
    );
  }

  String _threadStatus(Map<String, dynamic> thread) {
    final status = thread['status'];
    if (status is String) return status.toLowerCase();
    if (status is Map) {
      return _readString(status['type'])?.toLowerCase() ?? 'done';
    }
    return thread['active'] == true ? 'running' : 'done';
  }

  void _handleThreadCreated(Object? value) {
    final record =
        _sessionFromThread(value) ??
        SessionRecord(
          id: _readString(_asMap(_asMap(value)?['thread'])?['id']) ?? '',
          workspace: selectedWorkspace.value?.path ?? '',
          prompt: _pendingPrompt ?? '',
          status: 'running',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );
    if (record.id.isEmpty) return;
    _pendingSessionStart = false;
    currentSessionId.value = record.id;
    timelineSessionRunning.value = true;
    _markSessionRunningForNotification(record.id);
    _requestedEventsSessionId = record.id;
    _requestedEventsPrompt = _pendingPrompt ?? record.prompt;
    sessions.removeWhere((item) => item.id == record.id);
    sessions.insert(0, record);
    events.add(const SessionEvent(kind: 'running', text: '正在启动 Codex 任务...'));
    _bumpTimelineRevision();
    final prompt = _pendingPrompt;
    _pendingPrompt = null;
    if (prompt != null && prompt.isNotEmpty) {
      _sendCommand('turn.start', {
        'text': prompt,
        if ((selectedWorkspace.value?.path ?? '').trim().isNotEmpty)
          'cwd': selectedWorkspace.value!.path,
      }, threadId: record.id);
    }
  }

  void _handleThreadReadResult(Object? value) {
    final map = _asMap(value);
    final thread = _asMap(map?['thread']) ?? map;
    if (thread == null) return;
    final sessionId =
        _readString(thread['id']) ?? _requestedEventsSessionId ?? '';
    if (sessionId != _requestedEventsSessionId) return;
    final loaded = <SessionEvent>[];
    final prompt = _requestedEventsPrompt;
    if (prompt != null && prompt.trim().isNotEmpty) {
      loaded.add(SessionEvent(kind: 'user', text: prompt.trim()));
    }
    for (final turn in _asList(thread['turns'])) {
      final turnMap = _asMap(turn);
      if (turnMap == null) continue;
      for (final item in _asList(turnMap['items'])) {
        final event = _eventFromCodexItem(item);
        if (event != null) loaded.add(event);
      }
    }
    if (loaded.isEmpty) return;
    final merged = _mergeLiveEvents(loaded);
    if (!_hasSameTimelineEvents(events, merged)) {
      events.assignAll(merged);
      _bumpTimelineRevision();
    }
  }

  SessionEvent? _eventFromCodexItem(Object? value) {
    final item = _asMap(value);
    if (item == null) return null;
    final type = (_readString(item['type']) ?? '').toLowerCase();
    final text = _extractText(item);
    if (text.isEmpty && type.isEmpty) return null;
    final kind = type.contains('message') || type.contains('text')
        ? 'assistant'
        : type.contains('command') || type.contains('tool')
        ? 'tool_call'
        : type.contains('reason')
        ? 'reasoning'
        : 'event';
    return SessionEvent(kind: kind, text: text.isEmpty ? type : text);
  }

  void _handleCodexEvent(Map<String, dynamic> message) {
    final event = _asMap(message['event']);
    if (event == null) return;
    final type = _readString(event['type']) ?? '';
    final data = _asMap(event['data']) ?? const <String, dynamic>{};
    final threadId =
        _readString(message['threadId']) ??
        _readString(data['threadId']) ??
        currentSessionId.value;
    if (threadId != null &&
        threadId.isNotEmpty &&
        currentSessionId.value == null) {
      currentSessionId.value = threadId;
    }
    switch (type) {
      case 'thread.created':
      case 'thread.updated':
        final record = _sessionFromThread(data);
        if (record != null) {
          sessions.removeWhere((item) => item.id == record.id);
          sessions.insert(0, record);
          _deriveWorkspaces(sessions);
        }
      case 'turn.started':
        _currentTurnId =
            _readString(message['turnId']) ??
            _readString(data['turnId']) ??
            _readString(_asMap(data['turn'])?['id']);
        if (threadId != null && threadId.isNotEmpty) {
          currentSessionId.value = threadId;
          timelineSessionRunning.value = true;
          _markSessionRunningForNotification(threadId);
        }
        _appendSessionEvent(
          const SessionEvent(kind: 'running', text: 'Codex 正在执行...'),
        );
      case 'message.assistant.delta':
        _appendSessionEvent(
          SessionEvent(kind: 'assistant', text: _extractText(data)),
        );
      case 'reasoning.delta':
        _appendSessionEvent(
          SessionEvent(kind: 'reasoning', text: _extractText(data)),
        );
      case 'tool.output':
        _appendSessionEvent(
          SessionEvent(kind: 'tool_call', text: _extractText(data)),
        );
      case 'diff.updated':
        _appendSessionEvent(
          SessionEvent(kind: 'git_change', text: _extractText(data)),
        );
      case 'turn.completed':
        final text = _extractText(data);
        _appendSessionEvent(
          SessionEvent(kind: 'done', text: text.isEmpty ? 'Codex 任务已完成' : text),
        );
        _finishCurrentSession(
          status: TaskNotificationStatus.completed,
          sessionId: threadId,
        );
      case 'turn.failed':
        final extracted = _extractText(data);
        final text = extracted.isEmpty ? 'Codex 任务失败' : extracted;
        _appendSessionEvent(SessionEvent(kind: 'error', text: text));
        _finishCurrentSession(
          status: TaskNotificationStatus.failed,
          sessionId: threadId,
          message: text,
        );
      case 'turn.interrupted':
        _appendSessionEvent(
          const SessionEvent(kind: 'interrupted', text: '已被用户中断。'),
        );
        _finishCurrentSession(
          status: TaskNotificationStatus.interrupted,
          sessionId: threadId,
        );
      case 'approval.requested':
        lastError.value = 'Codex 请求审批，请在主机端处理。';
      default:
        final text = _extractText(data);
        if (text.isNotEmpty) {
          _appendSessionEvent(SessionEvent(kind: 'event', text: text));
        }
    }
  }

  void _finishCurrentSession({
    required TaskNotificationStatus status,
    String? sessionId,
    String? message,
  }) {
    final id = sessionId ?? currentSessionId.value;
    if (message != null &&
        message.isNotEmpty &&
        status == TaskNotificationStatus.failed) {
      lastError.value = message;
    }
    if (id != null && id.isNotEmpty) _markSessionTerminal(id);
    unawaited(
      _notifySessionFinishedOnce(
        status: status,
        sessionId: id,
        errorMessage: message,
      ),
    );
    currentSessionId.value = null;
    _currentTurnId = null;
    timelineSessionRunning.value = false;
    _pendingSessionStart = false;
    _pendingPrompt = null;
    _sendCommand('thread.list', {'limit': 100});
  }

  void _applyHostStatus(Object? value) {
    final map = _asMap(value);
    if (map == null) return;
    final appServer = _asMap(map['appServer']) ?? map;
    final version = _readString(appServer['version']) ?? '';
    if (version.isNotEmpty) {
      composerContext.value = composerContext.value.copyWith(
        codexVersion: version,
        bridgeVersion: 'relay-protocol-v1',
        transport: 'Relay',
      );
    }
  }

  void _sendCommand(
    String type,
    Map<String, dynamic> command, {
    String? threadId,
    String? turnId,
  }) {
    if (!connected.value ||
        targetDeviceId.value.isEmpty ||
        spaceId.value.isEmpty) {
      return;
    }
    final requestId = RelayProtocol.randomId('req');
    _outgoingSequence += 1;
    _pendingCommands[requestId] = _PendingCommand(type);
    final sent = _sendRaw(
      RelayProtocol.command(
        requestId: requestId,
        spaceId: spaceId.value,
        deviceId: deviceId.value,
        targetDeviceId: targetDeviceId.value,
        sequence: _outgoingSequence,
        command: {'type': type, ...command},
        threadId: threadId,
        turnId: turnId,
      ),
    );
    if (!sent) _pendingCommands.remove(requestId);
  }

  bool _sendRaw(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return false;
    final encoded = jsonEncode(frame);
    if (utf8.encode(encoded).length > _maxFrameSize) {
      lastError.value = 'Relay 消息超过 maxFrameSize 限制';
      return false;
    }
    socket.add(encoded);
    return true;
  }

  bool _rememberIncomingMessage(String messageId) {
    final added = _seenIncomingMessageIds.add(messageId);
    while (_seenIncomingMessageIds.length > 2048) {
      _seenIncomingMessageIds.remove(_seenIncomingMessageIds.first);
    }
    return added;
  }

  void _acceptIncomingSequence(Object? value) {
    if (value is num &&
        value.isFinite &&
        value.toInt() > _lastIncomingSequence) {
      _lastIncomingSequence = value.toInt();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (connected.value) _sendRaw(RelayProtocol.ping());
    });
  }

  Map<String, dynamic>? _asMap(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<Object?> _asList(Object? value) =>
      value is List ? List<Object?>.from(value) : const [];

  String? _readString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _dateString(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      ).toUtc().toIso8601String();
    }
    return _readString(value) ?? '';
  }

  String _extractText(Map<String, dynamic> map) {
    for (final key in const [
      'delta',
      'text',
      'message',
      'output',
      'summary',
      'content',
      'preview',
    ]) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
      if (value is Map) {
        final nested = _extractText(Map<String, dynamic>.from(value));
        if (nested.isNotEmpty) return nested;
      }
      if (value is List) {
        final text = value
            .whereType<Map>()
            .map((item) => _extractText(Map<String, dynamic>.from(item)))
            .where((item) => item.isNotEmpty)
            .join();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  void _handleDone() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    connected.value = false;
    connectionLabel.value = 'offline';
    _socket = null;
    _socketSubscription = null;
    _scheduleReconnect();
  }

  void _handleSocketError(Object error) {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    connected.value = false;
    connectionLabel.value = 'failed';
    _fail(error);
    _scheduleReconnect();
  }

  void _refreshLiveTimeline() {
    if (!connected.value) return;
    _sendCommand('thread.list', {'limit': 100});
    if (_requestedEventsSessionId != null) {
      _sendCommand('thread.read', {}, threadId: _requestedEventsSessionId);
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
    _sendCommand('thread.read', {}, threadId: latest.id);
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

  bool _isLiveStatusEvent(SessionEvent event) {
    return event.kind == 'running' || event.kind == 'tool_call';
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

  Future<void> _loadStoredCredentials() async {
    var shouldAutoConnect = false;
    try {
      // Remove the private key used by the deleted legacy Bridge protocol.
      await _storage.delete(key: 'recodex_device_key');
      final storedBaseUrl = await _storage.read(key: 'recodex_base_url');
      final storedSpaceId = await _storage.read(key: 'recodex_space_id');
      final storedTargetDeviceId = await _storage.read(
        key: 'recodex_target_device_id',
      );
      final storedDeviceName = await _storage.read(key: 'recodex_device_name');
      final storedDeviceId = await _storage.read(key: 'recodex_device_id');
      final storedDeviceKey = await _storage.read(
        key: 'recodex_endpoint_private_key',
      );
      final storedPairingToken = await _storage.read(
        key: 'recodex_pairing_token',
      );
      final storedEndpointGrant = await _storage.read(
        key: 'recodex_endpoint_grant',
      );
      final storedTokenExpiresAt = await _storage.read(
        key: 'recodex_token_expires_at',
      );
      final storedGrantExpiresAt = await _storage.read(
        key: 'recodex_grant_expires_at',
      );
      _storedWorkspaceName = await _storage.read(
        key: 'recodex_selected_workspace_name',
      );
      _storedWorkspacePath = await _storage.read(
        key: 'recodex_selected_workspace_path',
      );
      if (storedBaseUrl != null && storedBaseUrl.isNotEmpty) {
        baseUrl.value = _normalizeRelayUrl(storedBaseUrl);
      }
      if (storedSpaceId != null) spaceId.value = storedSpaceId;
      if (storedTargetDeviceId != null) {
        targetDeviceId.value = storedTargetDeviceId;
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
        try {
          final seed = RelayProtocol.decodeBase64Url(storedDeviceKey);
          _keyPair = await RelayProtocol.keyPairFromSeed(seed);
          deviceKey.value = storedDeviceKey;
          endpointPublicKey.value = await RelayProtocol.publicKey(_keyPair!);
        } catch (_) {
          deviceKey.value = '';
        }
      }
      if (storedPairingToken != null && storedPairingToken.isNotEmpty) {
        pairingToken.value = storedPairingToken;
      }
      if (storedEndpointGrant != null && storedEndpointGrant.isNotEmpty) {
        endpointGrant.value = storedEndpointGrant;
      }
      tokenExpiresAt.value = int.tryParse(storedTokenExpiresAt ?? '') ?? 0;
      grantExpiresAt.value = int.tryParse(storedGrantExpiresAt ?? '') ?? 0;
      _keyPair ??= await _loadOrCreateKeyPair();
      shouldAutoConnect =
          (pairingToken.value.isNotEmpty || endpointGrant.value.isNotEmpty) &&
          spaceId.value.isNotEmpty &&
          targetDeviceId.value.isNotEmpty;
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
    _keyPair ??= await _loadOrCreateKeyPair();
  }

  Future<SimpleKeyPair> _loadOrCreateKeyPair() async {
    if (deviceKey.value.isNotEmpty) {
      try {
        return await RelayProtocol.keyPairFromSeed(
          RelayProtocol.decodeBase64Url(deviceKey.value),
        );
      } catch (_) {
        deviceKey.value = '';
      }
    }
    final pair = await RelayProtocol.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    deviceKey.value = RelayProtocol.encodeBase64Url(seed);
    endpointPublicKey.value = await RelayProtocol.publicKey(pair);
    try {
      await _storage.write(
        key: 'recodex_endpoint_private_key',
        value: deviceKey.value,
      );
    } catch (_) {
      // Keep the key in memory when secure storage is unavailable.
    }
    return pair;
  }

  String _newDeviceId() {
    return 'flutter_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _storeConnectionHints() async {
    try {
      await _storage.write(key: 'recodex_base_url', value: baseUrl.value);
      await _storage.write(key: 'recodex_space_id', value: spaceId.value);
      await _storage.write(
        key: 'recodex_target_device_id',
        value: targetDeviceId.value,
      );
      await _storage.write(key: 'recodex_device_name', value: deviceName.value);
      await _storage.write(key: 'recodex_device_id', value: deviceId.value);
      await _storage.write(
        key: 'recodex_endpoint_private_key',
        value: deviceKey.value,
      );
      if (pairingToken.value.isNotEmpty) {
        await _storage.write(
          key: 'recodex_pairing_token',
          value: pairingToken.value,
        );
      }
      if (endpointGrant.value.isNotEmpty) {
        await _storage.write(
          key: 'recodex_endpoint_grant',
          value: endpointGrant.value,
        );
      }
      await _storage.write(
        key: 'recodex_token_expires_at',
        value: tokenExpiresAt.value.toString(),
      );
      await _storage.write(
        key: 'recodex_grant_expires_at',
        value: grantExpiresAt.value.toString(),
      );
    } catch (_) {
      // Keep the in-memory values for the current connection if storage is unavailable.
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
      inputSpaceId: spaceId.value,
      inputTargetDeviceId: targetDeviceId.value,
      inputEndpointId: deviceId.value,
      inputEndpointType: endpointType.value,
      inputEndpointGrant: endpointGrant.value,
    );
  }

  void _scheduleReconnect() {
    if (_manualDisconnect ||
        (pairingToken.value.isEmpty && endpointGrant.value.isEmpty) ||
        spaceId.value.isEmpty ||
        targetDeviceId.value.isEmpty ||
        _reconnectTimer != null) {
      return;
    }
    connectionLabel.value = 'reconnecting';
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      if (!_manualDisconnect &&
          !connected.value &&
          (pairingToken.value.isNotEmpty || endpointGrant.value.isNotEmpty) &&
          spaceId.value.isNotEmpty &&
          targetDeviceId.value.isNotEmpty) {
        unawaited(_autoConnect());
      }
    });
  }

  void _fail(Object error) {
    lastError.value = error.toString();
  }

  Future<String> _usableConnectToken(String suppliedToken) async {
    if (suppliedToken.isNotEmpty) pairingToken.value = suppliedToken;
    final hasGrant = endpointGrant.value.isNotEmpty;
    final expiresAt = tokenExpiresAt.value;
    final needsRefresh =
        (hasGrant || _forceTokenRefresh) &&
        (pairingToken.value.isEmpty ||
            _forceTokenRefresh ||
            (expiresAt > 0 &&
                expiresAt <= DateTime.now().millisecondsSinceEpoch + 60000));
    if (needsRefresh) {
      try {
        await _refreshConnectToken();
      } catch (error) {
        final stillUsable =
            !_forceTokenRefresh &&
            pairingToken.value.isNotEmpty &&
            (expiresAt == 0 ||
                expiresAt > DateTime.now().millisecondsSinceEpoch);
        if (!stillUsable) rethrow;
      }
    }
    if (pairingToken.value.isEmpty) {
      throw StateError('缺少 Connect Token');
    }
    return pairingToken.value;
  }

  Future<void> _refreshConnectToken() async {
    if (_keyPair == null || endpointGrant.value.isEmpty) {
      throw StateError('缺少 Endpoint Grant 或 Endpoint 私钥');
    }
    final relay = Uri.parse(baseUrl.value);
    if (relay.scheme == 'ws' && !_isLoopbackHost(relay.host)) {
      throw StateError('非本机 Relay 的 Token 刷新必须使用 HTTPS');
    }
    final endpoint = relay.replace(
      scheme: relay.scheme == 'wss' ? 'https' : 'http',
      path: '/api/connect-tokens/refresh',
      query: '',
      fragment: '',
    );
    final client = HttpClient();
    try {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode(
            await RelayProtocol.connectTokenRefreshRequest(
              keyPair: _keyPair!,
              endpointGrant: endpointGrant.value,
            ),
          ),
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bodyText = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(bodyText);
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      final dataValue = body['data'];
      final data = dataValue is Map
          ? Map<String, dynamic>.from(dataValue)
          : body;
      final relayCode = body['code'];
      final errorCode = data['errorCode'];
      final rejected =
          response.statusCode < 200 ||
          response.statusCode >= 300 ||
          (relayCode is num && relayCode.toInt() != 200);
      if (rejected) {
        throw StateError(
          '${errorCode ?? body['msg'] ?? 'auth.refresh_rejected'}',
        );
      }
      final nextToken = data['connectToken'];
      final nextExpiresAt = data['expiresAt'];
      if (nextToken is! String ||
          nextToken.length < 32 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(nextToken) ||
          nextExpiresAt is! num ||
          nextExpiresAt <= DateTime.now().millisecondsSinceEpoch) {
        throw StateError('Relay 返回了无效的刷新凭证');
      }
      pairingToken.value = nextToken;
      tokenExpiresAt.value = nextExpiresAt.toInt();
      _forceTokenRefresh = false;
      final nextGrantExpiresAt = data['grantExpiresAt'];
      if (nextGrantExpiresAt is num) {
        grantExpiresAt.value = nextGrantExpiresAt.toInt();
      }
      await _storeConnectionHints();
    } finally {
      client.close(force: true);
    }
  }

  bool _isLoopbackHost(String host) {
    return host == '127.0.0.1' || host == '::1' || host == 'localhost';
  }

  String _normalizeRelayUrl(String value) {
    var next = value.trim();
    if (next.isEmpty) next = 'ws://127.0.0.1:8788/v1/connect';
    if (!next.startsWith('ws://') && !next.startsWith('wss://')) {
      if (next.startsWith('http://')) {
        next = 'ws://${next.substring('http://'.length)}';
      } else if (next.startsWith('https://')) {
        next = 'wss://${next.substring('https://'.length)}';
      } else {
        next = 'wss://$next';
      }
    }
    final uri = Uri.parse(next);
    if (!uri.hasAuthority || uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw FormatException('Relay URL 必须是无 query/hash 的 WebSocket 地址');
    }
    final normalized = uri.path.isEmpty || uri.path == '/'
        ? uri.replace(path: '/v1/connect')
        : uri;
    if (normalized.path != '/v1/connect') {
      throw FormatException('Relay URL 必须使用 /v1/connect');
    }
    if (normalized.scheme == 'ws' && !_isLoopbackHost(normalized.host)) {
      throw FormatException('非本机 Relay 必须使用 wss:// 加密连接');
    }
    return normalized.toString();
  }
}

class _SessionLifecycle {
  bool observedRunning = false;
  bool visibleRunning = false;
  bool terminalObserved = false;
}

class _PendingCommand {
  const _PendingCommand(this.kind);

  final String kind;
}
