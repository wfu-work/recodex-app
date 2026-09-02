import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../models/bridge_models.dart';
import '../../services/relay_protocol.dart';
import '../../services/task_notification_controller.dart';
import '../settings/settings_preferences_controller.dart';

class BridgeController extends GetxController {
  static const _storageContainer = 'recodex';
  static const _commandTimeout = Duration(seconds: 35);
  static final _storage = GetStorage(_storageContainer);
  static const _legacySecureStorage = FlutterSecureStorage();
  static const _pairingsStorageKey = 'recodex_pairings_v2';
  static const _activePairingStorageKey = 'recodex_active_pairing_id_v2';
  static Future<void>? _storageReady;

  /// Initializes the local configuration container before any controller
  /// starts loading credentials. The guard also keeps widget tests and
  /// secondary entry points safe when they create the controller directly.
  static Future<void> initializeStorage() {
    final ready = _storageReady;
    if (ready != null) return ready;
    final pending = GetStorage.init(_storageContainer).then<void>((_) {});
    _storageReady = pending;
    return pending;
  }

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

  /// Saved Relay connections.  The active profile is mirrored into the
  /// connection observables below so existing screens can keep reacting to
  /// the same data flow.
  final pairings = <PairingProfile>[].obs;
  final activePairingId = RxnString();

  final workspaces = <WorkspaceInfo>[].obs;
  final sessions = <SessionRecord>[].obs;
  final events = <SessionEvent>[].obs;
  final selectedWorkspace = Rxn<WorkspaceInfo>();

  /// The task currently shown in the main conversation view. This is kept
  /// separate from [currentSessionId], which is also used for an active turn.
  final selectedSessionId = RxnString();
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
  bool _hadOnlineConnection = false;
  bool _pendingSessionStart = false;
  bool _interruptRequested = false;
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
  String? _storedSessionId;
  bool _sessionRestoreAttempted = false;
  final _sessionLifecycles = <String, _SessionLifecycle>{};
  final _notifiedTerminalSessions = <String>{};

  bool get canUseWorkspace =>
      connected.value && selectedWorkspace.value != null;
  bool get hasDeviceKey => deviceKey.value.isNotEmpty;

  PairingProfile? get activePairing {
    final id = activePairingId.value;
    if (id == null) return null;
    return pairingById(id);
  }

  PairingProfile? pairingById(String id) {
    for (final profile in pairings) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  PairingProfile createDraftPairing() {
    return PairingProfile(
      id: 'pairing_${DateTime.now().microsecondsSinceEpoch}',
      name: '',
      baseUrl: baseUrl.value,
      spaceId: '',
      deviceName: deviceName.value,
      deviceId: _newDeviceId(),
      targetDeviceId: '',
      endpointType: endpointType.value,
      deviceKey: '',
      endpointPublicKey: '',
      pairingToken: '',
      endpointGrant: '',
      tokenExpiresAt: 0,
      grantExpiresAt: 0,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Creates (or restores) the Ed25519 identity for a pairing editor.
  ///
  /// This deliberately does not write to secure storage. The caller can show
  /// the public key immediately, let the user copy it into relay-web, and only
  /// persist the private seed together with the pairing after an explicit save.
  Future<EndpointKeyMaterial> prepareEndpointKey({String? deviceKey}) async {
    SimpleKeyPair pair;
    final encodedSeed = deviceKey?.trim() ?? '';
    if (encodedSeed.isNotEmpty) {
      try {
        pair = await RelayProtocol.keyPairFromSeed(
          RelayProtocol.decodeBase64Url(encodedSeed),
        );
      } catch (_) {
        pair = await RelayProtocol.newKeyPair();
      }
    } else {
      pair = await RelayProtocol.newKeyPair();
    }
    final seed = await pair.extractPrivateKeyBytes();
    return EndpointKeyMaterial(
      deviceKey: RelayProtocol.encodeBase64Url(seed),
      publicKey: await RelayProtocol.publicKey(pair),
    );
  }

  PairingProfile _profileFromState({required String name, String? id}) {
    final previous = id == null ? activePairing : pairingById(id);
    return PairingProfile(
      id:
          id ??
          previous?.id ??
          'pairing_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      baseUrl: baseUrl.value,
      spaceId: spaceId.value,
      deviceName: deviceName.value,
      deviceId: deviceId.value,
      targetDeviceId: targetDeviceId.value,
      endpointType: endpointType.value,
      deviceKey: deviceKey.value,
      endpointPublicKey: endpointPublicKey.value,
      pairingToken: pairingToken.value,
      endpointGrant: endpointGrant.value,
      tokenExpiresAt: tokenExpiresAt.value,
      grantExpiresAt: grantExpiresAt.value,
      selectedWorkspaceName: _storedWorkspaceName,
      selectedWorkspacePath: _storedWorkspacePath,
      selectedSessionId: _storedSessionId,
      createdAt: previous?.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> upsertPairing(
    PairingProfile profile, {
    bool connect = true,
  }) async {
    await _ensureCredentialsLoaded();
    final normalized = profile.copyWith(
      baseUrl: _normalizeRelayUrl(profile.baseUrl),
      name: profile.name.trim(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    final index = pairings.indexWhere((item) => item.id == normalized.id);
    if (index < 0) {
      pairings.add(normalized);
    } else {
      pairings[index] = normalized;
    }
    activePairingId.value = normalized.id;
    await _persistActivePairingId();
    await disconnect(silent: true);
    await _applyPairing(normalized);
    _resetHostState();
    await _persistPairings();
    if (connect && normalized.isComplete) {
      await _autoConnect();
    }
  }

  Future<void> switchPairing(String id, {bool autoConnect = true}) async {
    await _ensureCredentialsLoaded();
    final profile = pairingById(id);
    if (profile == null) return;
    if (activePairingId.value == id) {
      return;
    }
    if (activePairingId.value != null) {
      await _storeConnectionHints();
    }
    await disconnect(silent: true);
    activePairingId.value = id;
    await _persistActivePairingId();
    await _applyPairing(profile);
    _resetHostState();
    if (autoConnect && profile.isComplete) {
      await _autoConnect();
    }
  }

  Future<void> deletePairing(String id) async {
    await _ensureCredentialsLoaded();
    final wasActive = activePairingId.value == id;
    pairings.removeWhere((profile) => profile.id == id);
    if (!wasActive) {
      await _persistPairings();
      return;
    }
    await disconnect(silent: true);
    if (pairings.isEmpty) {
      activePairingId.value = null;
      await _persistActivePairingId();
      _resetToEmptyConfiguration();
    } else {
      final next = pairings.first;
      activePairingId.value = next.id;
      await _persistActivePairingId();
      await _applyPairing(next);
      _resetHostState();
      if (next.isComplete) await _autoConnect();
    }
    await _persistPairings();
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadStoredCredentials());
    unawaited(_applySavedTaskPreferences());
  }

  @override
  void onClose() {
    stopLiveTimelineRefresh();
    unawaited(disconnect(silent: true));
    super.onClose();
  }

  Future<void> _applyPairing(PairingProfile profile) async {
    baseUrl.value = _normalizeRelayUrl(profile.baseUrl);
    spaceId.value = profile.spaceId;
    deviceName.value = profile.deviceName.trim().isEmpty
        ? 'Flutter phone'
        : profile.deviceName;
    deviceId.value = profile.deviceId.trim().isEmpty
        ? _newDeviceId()
        : profile.deviceId;
    targetDeviceId.value = profile.targetDeviceId;
    endpointType.value = profile.endpointType.trim().isEmpty
        ? 'app'
        : profile.endpointType;
    deviceKey.value = profile.deviceKey;
    endpointPublicKey.value = profile.endpointPublicKey;
    pairingToken.value = profile.pairingToken;
    endpointGrant.value = profile.endpointGrant;
    tokenExpiresAt.value = profile.tokenExpiresAt;
    grantExpiresAt.value = profile.grantExpiresAt;
    _storedWorkspaceName = profile.selectedWorkspaceName;
    _storedWorkspacePath = profile.selectedWorkspacePath;
    _storedSessionId = profile.selectedSessionId;
    _sessionRestoreAttempted = false;
    _keyPair = null;
  }

  void _resetHostState() {
    lastError.value = '';
    workspaces.clear();
    sessions.clear();
    events.clear();
    selectedWorkspace.value = null;
    gitSnapshot.value = null;
    composerContext.value = ComposerContext.fallback;
    if (Get.isRegistered<SettingsPreferencesController>()) {
      applyTaskPreferences(Get.find<SettingsPreferencesController>());
    }
    currentSessionId.value = null;
    selectedSessionId.value = null;
    timelineSessionRunning.value = false;
    timelineRevision.value += 1;
    relaySessionId.value = '';
    _outgoingSequence = 0;
    _lastIncomingSequence = 0;
    _pendingSessionStart = false;
    _interruptRequested = false;
    _pendingPrompt = null;
    _currentTurnId = null;
    _pendingHelloRequestId = null;
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    _pendingCommands.clear();
    _seenIncomingMessageIds.clear();
    _sessionLifecycles.clear();
    _notifiedTerminalSessions.clear();
    _sessionRestoreAttempted = false;
  }

  void _resetToEmptyConfiguration() {
    baseUrl.value = 'ws://127.0.0.1:8788/v1/connect';
    spaceId.value = '';
    deviceName.value = 'Flutter phone';
    deviceId.value = _newDeviceId();
    targetDeviceId.value = '';
    endpointType.value = 'app';
    deviceKey.value = '';
    endpointPublicKey.value = '';
    pairingToken.value = '';
    endpointGrant.value = '';
    tokenExpiresAt.value = 0;
    grantExpiresAt.value = 0;
    _storedWorkspaceName = null;
    _storedWorkspacePath = null;
    _storedSessionId = null;
    _sessionRestoreAttempted = false;
    _keyPair = null;
    _resetHostState();
  }

  Future<void> _persistPairings() async {
    try {
      await initializeStorage();
      await _storage.write(
        _pairingsStorageKey,
        pairings.map((profile) => profile.toJson()).toList(),
      );
    } catch (_) {
      // Keep in-memory profiles when local storage is unavailable.
    }
  }

  Future<void> _persistActivePairingId() async {
    try {
      await initializeStorage();
      final id = activePairingId.value;
      if (id == null || id.isEmpty) {
        await _storage.remove(_activePairingStorageKey);
      } else {
        await _storage.write(_activePairingStorageKey, id);
      }
    } catch (_) {
      // Keep the active profile in memory when local storage is unavailable.
    }
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
        _keyPair = null;
        deviceKey.value = '';
        endpointPublicKey.value = '';
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
          'Relay 配置不完整：需要 Relay 连接地址、空间 ID、本机接入端 ID、目标主机接入端 ID，以及连接令牌或接入端授权凭证',
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

  /// Checks a Relay pairing without changing the active profile or opening a
  /// persistent app connection. This is used by the pairing editor so users
  /// can verify the endpoint credentials before saving them.
  ///
  /// Returns `null` when the Relay accepts the handshake, otherwise a
  /// user-facing error message. The endpoint key is supplied by the editor's
  /// in-memory draft and is never written to secure storage here.
  Future<String?> testConnection({
    required String inputBaseUrl,
    required String token,
    required String inputDeviceName,
    required String inputSpaceId,
    required String inputTargetDeviceId,
    required String inputEndpointId,
    required String inputEndpointType,
    required String inputDeviceKey,
  }) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    Timer? timeout;
    final result = Completer<String?>();

    void complete(String? error) {
      if (!result.isCompleted) result.complete(error);
    }

    try {
      final normalizedBaseUrl = _normalizeRelayUrl(inputBaseUrl);
      final nextSpaceId = inputSpaceId.trim();
      final nextTargetDeviceId = inputTargetDeviceId.trim();
      final nextEndpointId = inputEndpointId.trim();
      final nextEndpointType = inputEndpointType.trim().isEmpty
          ? 'app'
          : inputEndpointType.trim();
      final connectToken = token.trim();
      final encodedKey = inputDeviceKey.trim();
      if (nextSpaceId.isEmpty ||
          nextTargetDeviceId.isEmpty ||
          nextEndpointId.isEmpty) {
        return '请先填写空间 ID、目标主机接入端 ID 和本机接入端 ID。';
      }
      if (connectToken.isEmpty) {
        return '请先填写连接令牌；接入端授权凭证用于后续自动续期。';
      }
      if (encodedKey.isEmpty) {
        return '接入端公钥尚未生成，请稍后再试。';
      }

      final keyPair = await RelayProtocol.keyPairFromSeed(
        RelayProtocol.decodeBase64Url(encodedKey),
      );
      socket = await WebSocket.connect(
        normalizedBaseUrl,
      ).timeout(const Duration(seconds: 10));
      subscription = socket.listen(
        (raw) {
          try {
            final decoded = _decodeTextMessage(raw);
            final type = decoded['type'] as String? ?? '';
            if (type == 'relay.error') {
              final code = decoded['code'] as String? ?? 'relay.error';
              final message = decoded['message'] as String? ?? 'Relay 拒绝了连接';
              complete('$code：$message');
              return;
            }
            if (type != 'connect.welcome') return;
            RelayProtocol.validateWelcome(decoded);
            if (decoded['spaceId'] != nextSpaceId ||
                decoded['endpointId'] != nextEndpointId) {
              complete('Relay 返回的空间 ID 或接入端 ID 与当前配置不一致。');
              return;
            }
            complete(null);
          } catch (error) {
            complete(error.toString());
          }
        },
        onError: (Object error) => complete(error.toString()),
        onDone: () => complete('Relay 在认证完成前关闭了连接。'),
        cancelOnError: false,
      );
      final hello = await RelayProtocol.connectHello(
        keyPair: keyPair,
        spaceId: nextSpaceId,
        endpointId: nextEndpointId,
        endpointType: nextEndpointType,
        endpointName: inputDeviceName.trim().isEmpty
            ? 'Flutter phone'
            : inputDeviceName.trim(),
        token: connectToken,
      );
      socket.add(jsonEncode(hello));
      timeout = Timer(const Duration(seconds: 10), () {
        complete('Relay 认证超时，请检查地址、令牌和网络连接。');
      });
      return await result.future;
    } catch (error) {
      return error.toString();
    } finally {
      timeout?.cancel();
      await subscription?.cancel();
      await socket?.close();
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
    _clearRemoteModels();
    _hadOnlineConnection = false;
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
    selectedSessionId.value = null;
    // An explicit project switch is a user choice. Do not immediately
    // replace it with the previously opened task while the new catalog is
    // synchronizing.
    _sessionRestoreAttempted = true;
    timelineSessionRunning.value = false;
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    events.clear();
    _bumpTimelineRevision();
    refreshContext();
    gitStatus(includeDiff: true);
    _loadLatestSessionEventsForSelectedWorkspace();
  }

  /// Selects a task from the sidebar and loads its persisted conversation.
  ///
  /// Codex keeps thread metadata and thread content as separate resources.
  /// The list response is therefore only used to paint the sidebar; the
  /// explicit read below hydrates the main conversation for the selected
  /// thread.
  void selectSession(SessionRecord session) {
    if (session.id.trim().isEmpty) return;

    final workspace = _workspaceForSession(session.workspace);
    if (workspace != null &&
        !_sameWorkspace(selectedWorkspace.value, workspace)) {
      selectedWorkspace.value = workspace;
      unawaited(_storeSelectedWorkspace(workspace));
      gitSnapshot.value = null;
      refreshContext();
      gitStatus(includeDiff: true);
    }

    selectedSessionId.value = session.id;
    currentSessionId.value = session.id;
    _sessionRestoreAttempted = true;
    _storedSessionId = session.id;
    unawaited(_storeSelectedSession(session.id));
    timelineSessionRunning.value = session.isRunning;
    _requestedEventsSessionId = session.id;
    _requestedEventsPrompt = session.prompt;
    events.clear();
    _bumpTimelineRevision();

    if (!connected.value) {
      lastError.value = '尚未连接 Relay，无法加载任务对话。';
      return;
    }
    _sendCommand('thread.read', {}, threadId: session.id);
  }

  /// Clears the visible transcript so the composer can start a fresh task.
  ///
  /// The last persisted task is intentionally kept in [_storedSessionId];
  /// that value is used to restore the previous task after a Relay reconnect.
  void startNewConversation() {
    currentSessionId.value = null;
    selectedSessionId.value = null;
    timelineSessionRunning.value = false;
    _pendingSessionStart = false;
    _interruptRequested = false;
    _pendingPrompt = null;
    _currentTurnId = null;
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    _sessionRestoreAttempted = true;
    events.clear();
    _bumpTimelineRevision();
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
    _interruptRequested = false;
    _pendingSessionStart = true;
    _pendingPrompt = trimmedPrompt;
    selectedSessionId.value = null;
    _sessionRestoreAttempted = true;
    _sendCommand('thread.create', {
      if (workspace.path.trim().isNotEmpty) 'cwd': workspace.path,
    });
  }

  void setComposerModel(String model) {
    final context = composerContext.value;
    final efforts = context.modelReasoningEfforts[model] ?? const <String>[];
    final effort = _resolveReasoningEffort(
      requested: context.reasoningEffort,
      available: efforts,
      advertisedDefault: context.modelDefaultReasoningEfforts[model],
    );
    composerContext.value = context.copyWith(
      model: model,
      reasoningEfforts: efforts,
      reasoningEffort: effort,
    );
  }

  void setReasoningEffort(String effort) {
    final available = composerContext.value.reasoningEfforts;
    if (available.isNotEmpty && !available.contains(effort)) return;
    composerContext.value = composerContext.value.copyWith(
      reasoningEffort: effort,
    );
  }

  void setPermissionMode(String mode) {
    permissionMode.value = mode;
  }

  /// Applies task defaults loaded from the settings page to the active
  /// composer. The remote host may still provide its own capability list;
  /// these values only select the user's preferred defaults.
  void applyTaskPreferences(SettingsPreferencesController preferences) {
    final model = preferences.defaultModel.value;
    final selectedModel = model == '自动选择' || model.trim().isEmpty
        ? composerContext.value.models.isEmpty
              ? composerContext.value.model
              : composerContext.value.models.first
        : model;
    final availableEfforts =
        composerContext.value.modelReasoningEfforts[selectedModel] ??
        composerContext.value.reasoningEfforts;
    final selectedEffort = _resolveReasoningEffort(
      requested: preferences.defaultReasoningEffort.value,
      available: availableEfforts,
      advertisedDefault:
          composerContext.value.modelDefaultReasoningEfforts[selectedModel],
    );
    composerContext.value = composerContext.value.copyWith(
      model: selectedModel,
      reasoningEffort: selectedEffort,
      reasoningEfforts: availableEfforts,
      requireConfirmGitWrite: preferences.confirmSensitiveActions.value,
      approvalPolicy: _approvalPolicyFor(
        preferences.defaultPermissionMode.value,
      ),
    );
    permissionMode.value = preferences.defaultPermissionMode.value;
  }

  /// Stops the active turn, including the short window while thread.create or
  /// turn.start is still waiting for a response from the host.
  void interrupt() {
    if (_pendingSessionStart) {
      _pendingSessionStart = false;
      _pendingPrompt = null;
      _pendingCommands.removeWhere(
        (_, command) => command.kind == 'thread.create',
      );
      currentSessionId.value = null;
      selectedSessionId.value = null;
      _currentTurnId = null;
      _interruptRequested = false;
      timelineSessionRunning.value = false;
      _appendSessionEvent(
        const SessionEvent(kind: 'interrupted', text: '已取消当前任务。'),
      );
      return;
    }

    final sessionId = currentSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return;
    final turnId = _currentTurnId;
    if (turnId == null || turnId.isEmpty) {
      _interruptRequested = true;
      return;
    }
    _sendCommand('turn.interrupt', {}, threadId: sessionId, turnId: turnId);
  }

  void _sendRequestedInterrupt() {
    if (!_interruptRequested) return;
    final sessionId = currentSessionId.value;
    final turnId = _currentTurnId;
    if (sessionId == null ||
        sessionId.isEmpty ||
        turnId == null ||
        turnId.isEmpty) {
      return;
    }
    _interruptRequested = false;
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
    _clearRemoteModels();
    _sendCommand('model.list', {'includeHidden': false, 'limit': 100});
    _sendCommand('host.get_status', {});
  }

  void startLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _refreshLiveTimeline();
    _liveTimelineTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshLiveTimeline();
    });
  }

  /// Refreshes the current workspace task list and selected task output once.
  /// The periodic refresh continues independently when the main page is open.
  void refreshProjectTasks() {
    _refreshLiveTimeline();
  }

  /// Requests a fresh thread snapshot so the sidebar can rebuild its project
  /// list even when reconnect recovery only has incremental events available.
  ///
  /// The sidebar action only needs the catalog request. A reconnect also asks
  /// for the event cursor so an interrupted conversation can be restored.
  void refreshProjects({bool recoverEvents = false}) {
    if (!connected.value) return;
    if (recoverEvents) {
      _sendCommand('sync.request', {
        if (_lastIncomingSequence > 0) 'lastSequence': _lastIncomingSequence,
      });
    }
    _sendCommand('thread.list', {'limit': 100});
  }

  void stopLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _liveTimelineTimer = null;
  }

  Future<void> clearStoredCredentials() async {
    await disconnect(silent: true);
    final active = activePairing;
    if (active != null) {
      final cleared = active.copyWith(
        deviceId: _newDeviceId(),
        deviceKey: '',
        endpointPublicKey: '',
        pairingToken: '',
        endpointGrant: '',
        tokenExpiresAt: 0,
        grantExpiresAt: 0,
      );
      final index = pairings.indexWhere((profile) => profile.id == active.id);
      if (index >= 0) pairings[index] = cleared;
      await _applyPairing(cleared);
      _resetHostState();
      await _persistPairings();
    } else {
      deviceKey.value = '';
      endpointPublicKey.value = '';
      _keyPair = null;
      deviceId.value = _newDeviceId();
      pairingToken.value = '';
      endpointGrant.value = '';
      tokenExpiresAt.value = 0;
      grantExpiresAt.value = 0;
    }
    _forceTokenRefresh = false;
    lastError.value = '';
    try {
      await initializeStorage();
      await Future.wait([
        _storage.remove('recodex_endpoint_private_key'),
        _storage.remove('recodex_device_key'),
        _storage.remove('recodex_device_id'),
        _storage.remove('recodex_pairing_token'),
        _storage.remove('recodex_endpoint_grant'),
        _storage.remove('recodex_token_expires_at'),
        _storage.remove('recodex_grant_expires_at'),
      ]);
      // Also clear the pre-GetStorage Keychain values so an explicit
      // credential reset cannot be undone by a later migration.
      await Future.wait([
        _legacySecureStorage.delete(key: _pairingsStorageKey),
        _legacySecureStorage.delete(key: _activePairingStorageKey),
        _legacySecureStorage.delete(key: 'recodex_endpoint_private_key'),
        _legacySecureStorage.delete(key: 'recodex_device_key'),
        _legacySecureStorage.delete(key: 'recodex_device_id'),
        _legacySecureStorage.delete(key: 'recodex_pairing_token'),
        _legacySecureStorage.delete(key: 'recodex_endpoint_grant'),
        _legacySecureStorage.delete(key: 'recodex_token_expires_at'),
        _legacySecureStorage.delete(key: 'recodex_grant_expires_at'),
      ]);
    } catch (_) {
      lastError.value = '本地配置存储不可用。';
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
    final shouldNotifyReconnect = _hadOnlineConnection && !connected.value;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _startHeartbeat();
    _maxFrameSize = (message['maxFrameSize'] as num).toInt();
    relaySessionId.value = message['sessionId'] as String? ?? '';
    connected.value = true;
    connectionLabel.value = 'online';
    _hadOnlineConnection = true;
    lastError.value = '';
    if (shouldNotifyReconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayReconnected(),
      );
    }
    if (selectedSessionId.value == null) {
      _sessionRestoreAttempted = false;
    }
    _clearRemoteModels();
    _pendingCommands.clear();
    unawaited(_storeConnectionHints());
    refreshProjects(recoverEvents: true);
    _sendCommand('model.list', {'includeHidden': false, 'limit': 100});
    _sendCommand('host.get_status', {});
  }

  void _handleRelayError(Map<String, dynamic> message) {
    final wasConnected = connected.value;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final code = message['code'] as String? ?? 'relay.error';
    final text = message['message'] as String? ?? 'Relay 连接被拒绝';
    lastError.value = '$code：$text';
    connected.value = false;
    connectionLabel.value = 'failed';
    if (wasConnected &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
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
      unawaited(_storeConnectionHints());
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
    if ((pending?.kind == 'thread.list' || pending?.kind == 'thread.read') &&
        _isTransientSyncError(lastError.value)) {
      lastError.value = '';
    }
    final result = message['result'];
    switch (pending?.kind) {
      case 'sync.request':
        _applySyncResult(result);
      case 'thread.list':
        _applyThreadListResult(result);
      case 'model.list':
        _applyModelListResult(result);
      case 'thread.create':
        _handleThreadCreated(result);
      case 'thread.read':
        _handleThreadReadResult(result);
      case 'turn.start':
        final map = _asMap(result);
        _currentTurnId =
            _readString(map?['turnId']) ??
            _readString(_asMap(map?['turn'])?['id']);
        _sendRequestedInterrupt();
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
      if (sessions.isEmpty || workspaces.isEmpty) {
        _sendCommand('thread.list', {'limit': 100});
      }
    } else {
      _applyThreadListResult(map['threads']);
      _applyHostStatus(map['status']);
    }
  }

  void _applyThreadListResult(Object? value) {
    final next = _dedupeSessions(
      _threadListItems(
        value,
      ).map(_sessionFromThread).whereType<SessionRecord>(),
    );
    _syncSessionCompletionNotifications(next);
    // App Server can briefly report an idle thread while its turn.started
    // event is already in flight. Keep the local running marker visible until
    // the matching terminal event arrives instead of making the sidebar
    // flicker back to a completed state on every catalog refresh.
    sessions.assignAll(next.map(_sessionWithLiveStatus));
    final selectedId = selectedSessionId.value;
    if (selectedId != null &&
        !next.any((session) => session.id == selectedId)) {
      selectedSessionId.value = null;
    }
    _deriveWorkspaces(next);
    selectedWorkspace.value ??= _restoreSelectedWorkspace();
    selectedWorkspace.value ??= _defaultWorkspace();
    _restoreLastSelectedSession(next);
    // The catalog refresh only updates an already selected timeline once.
    // Older Codex threads can contain megabytes of tool output, so forcing a
    // full read here would make the Relay connection flap while polling.
    _loadLatestSessionEventsForSelectedWorkspace();
  }

  /// Codex App Server has returned both `{data: [...]}` and direct arrays over
  /// its supported versions. Relay keeps that result opaque, so tolerate the
  /// common wrapper names here instead of making the sidebar depend on one
  /// server release.
  List<Object?> _threadListItems(Object? value) {
    var current = value;
    for (var depth = 0; depth < 3; depth++) {
      if (current is List) return List<Object?>.from(current);
      final map = _asMap(current);
      if (map == null) return const [];
      Object? next;
      for (final key in const [
        'data',
        'threads',
        'items',
        'results',
        'sessions',
        'result',
      ]) {
        if (map.containsKey(key)) {
          next = map[key];
          break;
        }
      }
      if (next == null) return const [];
      current = next;
    }
    return const [];
  }

  List<SessionRecord> _dedupeSessions(Iterable<SessionRecord> records) {
    final byId = <String, SessionRecord>{};
    final order = <String>[];
    for (final session in records) {
      final id = session.id.trim();
      if (id.isEmpty) continue;
      final previous = byId[id];
      if (previous == null) {
        order.add(id);
        byId[id] = session;
      } else if (session.updatedAtDate.isAfter(previous.updatedAtDate)) {
        byId[id] = session;
      }
    }
    return [for (final id in order) byId[id]!];
  }

  void _upsertSession(SessionRecord record) {
    final id = record.id.trim();
    if (id.isEmpty) return;
    record = _sessionWithLiveStatus(record);
    sessions.removeWhere((item) => item.id.trim() == id);
    sessions.insert(0, record);
  }

  SessionRecord _sessionWithLiveStatus(SessionRecord session) {
    if (session.isRunning) return session;
    final lifecycle = _sessionLifecycles[session.id.trim()];
    final selectedRunning =
        session.id.trim() == currentSessionId.value?.trim() &&
        timelineSessionRunning.value;
    if (lifecycle?.visibleRunning != true && !selectedRunning) return session;
    return session.copyWith(status: 'running');
  }

  void _restoreLastSelectedSession(List<SessionRecord> records) {
    if (_sessionRestoreAttempted || selectedSessionId.value != null) return;
    if (records.isEmpty) return;

    final storedId = _storedSessionId?.trim() ?? '';
    SessionRecord? selected;
    if (storedId.isNotEmpty) {
      for (final session in records) {
        if (session.id.trim() == storedId) {
          selected = session;
          break;
        }
      }
    }
    // Profiles created before selectedSessionId was introduced have no saved
    // task. The server returns newest-first, so opening the first non-archived
    // task is the least surprising migration fallback.
    selected ??= records.cast<SessionRecord?>().firstWhere(
      (session) => session != null && !session.isArchived,
      orElse: () => null,
    );
    if (selected == null) return;

    _sessionRestoreAttempted = true;
    final workspace = _workspaceForSession(selected.workspace);
    if (workspace != null &&
        !_sameWorkspace(selectedWorkspace.value, workspace)) {
      selectedWorkspace.value = workspace;
      unawaited(_storeSelectedWorkspace(workspace));
    }
    selectedSessionId.value = selected.id;
    currentSessionId.value = selected.id;
    timelineSessionRunning.value = selected.isRunning;
    // Leave the read request unset so the normal timeline loader issues a
    // fresh thread.read for the restored task below.
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = selected.prompt;
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
    final id =
        _readString(thread['id']) ??
        _readString(thread['threadId']) ??
        _readString(thread['sessionId']);
    if (id == null || id.isEmpty) return null;
    final workspace = _threadWorkspace(thread);
    final title =
        _readString(thread['name']) ?? _readString(thread['title']) ?? '';
    // Keep the raw preview for thread/read prompt matching. The sidebar uses
    // SessionRecord.displayTitle, which prefers the official name and cleans
    // legacy attachment metadata when a name is unavailable.
    final prompt = _readString(thread['preview']) ?? title;
    final status = _threadStatus(thread);
    final created = _dateString(thread['createdAt'] ?? thread['created_at']);
    final updated = _dateString(thread['updatedAt'] ?? thread['updated_at']);
    return SessionRecord(
      id: id,
      workspace: workspace,
      prompt: prompt,
      status: status,
      createdAt: created,
      updatedAt: updated.isEmpty ? created : updated,
      title: title,
      isPinned: _readBool(
        thread['isPinned'] ?? thread['is_pinned'] ?? thread['pinned'],
      ),
      isArchived:
          _readBool(
            thread['isArchived'] ?? thread['is_archived'] ?? thread['archived'],
          ) ||
          status == 'archived',
    );
  }

  String _threadWorkspace(Map<String, dynamic> thread) {
    final direct = <String?>[
      _readString(thread['cwd']),
      _readString(thread['workingDirectory']),
      _readString(thread['workspacePath']),
      _readString(thread['projectPath']),
    ];
    for (final value in direct) {
      if (value != null) return value;
    }

    final workspace = _asMap(thread['workspace']);
    final nestedWorkspace = _readString(workspace?['path']);
    if (nestedWorkspace != null) return nestedWorkspace;
    final project = _asMap(thread['project']);
    final nestedProject = _readString(project?['path']);
    if (nestedProject != null) return nestedProject;

    // `path` is a rollout JSONL file in current Codex versions. It is useful
    // as a fallback for older servers only when it is clearly a directory,
    // never when it points at Codex's session archive.
    final path = _readString(thread['path']);
    if (path != null && !_looksLikeSessionArtifact(path)) return path;
    return _readString(thread['workspace']) ?? '';
  }

  bool _looksLikeSessionArtifact(String value) {
    final normalized = value.replaceAll('\\', '/').toLowerCase();
    return normalized.endsWith('.jsonl') ||
        normalized.contains('/.codex/sessions') ||
        normalized.contains('/codex/sessions');
  }

  String _threadStatus(Map<String, dynamic> thread) {
    // Some App Server versions expose the lifecycle both as a status object
    // and as a top-level active/running flag. The explicit flag must win over
    // a stale idle status while a turn is still executing.
    if (_readBool(thread['active']) || _readBool(thread['running'])) {
      return 'running';
    }
    final status = thread['status'];
    if (status is String) return _normalizeThreadStatus(status);
    if (status is Map) {
      return _normalizeThreadStatus(
        _readString(status['type']) ??
            _readString(status['state']) ??
            _readString(status['status']) ??
            'done',
      );
    }
    return 'done';
  }

  String _normalizeThreadStatus(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'active' ||
      'running' ||
      'inprogress' ||
      'in_progress' ||
      'processing' ||
      'queued' ||
      'starting' ||
      'pending' ||
      'executing' ||
      'working' => 'running',
      'idle' || 'notloaded' => 'done',
      _ => normalized,
    };
  }

  bool _readBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
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
    selectedSessionId.value = record.id;
    _storedSessionId = record.id;
    _sessionRestoreAttempted = true;
    unawaited(_storeSelectedSession(record.id));
    timelineSessionRunning.value = true;
    _markSessionRunningForNotification(record.id);
    _requestedEventsSessionId = record.id;
    _requestedEventsPrompt = _pendingPrompt ?? record.prompt;
    _upsertSession(record);
    _appendSessionEvent(
      const SessionEvent(kind: 'running', text: '正在启动 Codex 任务...'),
    );
    final prompt = _pendingPrompt;
    _pendingPrompt = null;
    if (prompt != null && prompt.isNotEmpty) {
      final context = composerContext.value;
      _sendCommand('turn.start', {
        'text': prompt,
        if ((selectedWorkspace.value?.path ?? '').trim().isNotEmpty)
          'cwd': selectedWorkspace.value!.path,
        if (context.model.trim().isNotEmpty) 'model': context.model,
        if (context.reasoningEfforts.contains(context.reasoningEffort))
          'effort': context.reasoningEffort,
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
    var promptWasAdded = false;
    if (prompt != null && prompt.trim().isNotEmpty) {
      loaded.add(SessionEvent(kind: 'user', text: prompt.trim()));
      promptWasAdded = true;
    }
    for (final turn in _asList(thread['turns'])) {
      final turnMap = _asMap(turn);
      if (turnMap == null) continue;
      for (final item in _asList(turnMap['items'])) {
        final event = _eventFromCodexItem(item);
        if (event == null) continue;
        if (promptWasAdded &&
            event.kind == 'user' &&
            (_matchesRequestedPrompt(event.text, prompt!) ||
                (event.text.trim().isEmpty && event.attachments.isNotEmpty))) {
          final promptEvent = loaded.first;
          loaded[0] = SessionEvent(
            kind: promptEvent.kind,
            text: promptEvent.text,
            time: event.time ?? promptEvent.time,
            usage: event.usage ?? promptEvent.usage,
            attachments: _mergeEventAttachments(
              promptEvent.attachments,
              event.attachments,
            ),
          );
          promptWasAdded = false;
          continue;
        }
        loaded.add(event);
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
    final attachments = _extractAttachments(item);
    final usage = _extractTokenUsage(item);
    if (text.isEmpty && type.isEmpty && attachments.isEmpty && usage == null) {
      return null;
    }
    final usageEvent =
        usage != null &&
        text.isEmpty &&
        attachments.isEmpty &&
        (type.contains('usage') || type.contains('token'));
    final kind = type == 'usermessage' || type.contains('user_message')
        ? 'user'
        : type.contains('message') || type.contains('text')
        ? 'assistant'
        : type.contains('command') || type.contains('tool')
        ? 'tool_call'
        : type.contains('reason')
        ? 'reasoning'
        : usageEvent
        ? 'token_usage'
        : 'event';
    return SessionEvent(
      kind: kind,
      // Attachment-only items do not have user-visible copy. Leaving their
      // text empty lets the timeline render the thumbnail without leaking
      // protocol type names such as "userMessage" or "image".
      text: text.isEmpty && attachments.isEmpty ? type : text,
      usage: usage,
      attachments: attachments,
    );
  }

  void _handleCodexEvent(Map<String, dynamic> message) {
    final event = _asMap(message['event']);
    if (event == null) return;
    final type = _readString(event['type']) ?? '';
    final data = _asMap(event['data']) ?? const <String, dynamic>{};
    final eventUsage = _extractTokenUsage(data);
    final threadId =
        _readString(message['threadId']) ??
        _readString(data['threadId']) ??
        currentSessionId.value;
    if (threadId != null && threadId.isNotEmpty) {
      final selectedId = selectedSessionId.value?.trim();
      // A blank transcript is an intentional new-conversation state. Ignore
      // events from background tasks until the pending new thread is selected,
      // otherwise an old task could repopulate the freshly cleared view.
      if ((selectedId == null || selectedId.isEmpty) && !_pendingSessionStart) {
        return;
      }
      if (selectedId != null &&
          selectedId.isNotEmpty &&
          threadId != selectedId) {
        return;
      }
    }
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
          _upsertSession(record);
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
        _sendRequestedInterrupt();
      case 'message.assistant.delta':
        _appendSessionEvent(
          SessionEvent(
            kind: 'assistant',
            text: _extractText(data),
            usage: eventUsage,
            attachments: _extractAttachments(data),
          ),
        );
      case 'reasoning.delta':
        _appendSessionEvent(
          SessionEvent(
            kind: 'reasoning',
            text: _extractText(data),
            usage: eventUsage,
            attachments: _extractAttachments(data),
          ),
        );
      case 'tool.output':
        _appendSessionEvent(
          SessionEvent(
            kind: 'tool_call',
            text: _extractText(data),
            usage: eventUsage,
            attachments: _extractAttachments(data),
          ),
        );
      case 'token.usage':
      case 'token_usage':
      case 'usage.updated':
        if (eventUsage != null) {
          _appendSessionEvent(
            SessionEvent(kind: 'token_usage', text: '', usage: eventUsage),
          );
        }
      case 'diff.updated':
        _appendSessionEvent(
          SessionEvent(kind: 'git_change', text: _extractText(data)),
        );
      case 'turn.completed':
        final text = _extractText(data);
        _appendSessionEvent(
          SessionEvent(
            kind: 'done',
            text: text.isEmpty ? 'Codex 任务已完成' : text,
            usage: eventUsage,
          ),
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
        final attachments = _extractAttachments(data);
        if (text.isNotEmpty || attachments.isNotEmpty) {
          _appendSessionEvent(
            SessionEvent(kind: 'event', text: text, attachments: attachments),
          );
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
    _interruptRequested = false;
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

  void _applyModelListResult(Object? value) {
    final map = _asMap(value);
    final rawModels = map == null ? value : (map['data'] ?? map['models']);
    final parsed = ComposerContext.fromJson({
      'model': composerContext.value.model,
      'reasoningEffort': composerContext.value.reasoningEffort,
      'models': _asList(rawModels),
    });
    final models = [...parsed.models];
    final labels = {...parsed.modelLabels};
    var remoteDefault = '';

    for (final raw in _asList(rawModels)) {
      final model = _asMap(raw);
      if (model != null && model['hidden'] == true) continue;
      final id = model == null
          ? _readString(raw)
          : (_readString(model['model']) ?? _readString(model['id']));
      if (id == null) continue;
      if (model?['isDefault'] == true) remoteDefault = id;
    }

    // Keep the App Server's default first so the existing "自动选择"
    // preference resolves to the same model as the official picker even when
    // the server does not order its response by default status.
    if (remoteDefault.isNotEmpty &&
        (models.isEmpty || models.first != remoteDefault)) {
      models.remove(remoteDefault);
      models.insert(0, remoteDefault);
    }

    final current = composerContext.value.model;
    final selected = models.contains(current)
        ? current
        : remoteDefault.isNotEmpty
        ? remoteDefault
        : models.isEmpty
        ? ''
        : models.first;
    final selectedEfforts =
        parsed.modelReasoningEfforts[selected] ?? const <String>[];
    final selectedEffort = _resolveReasoningEffort(
      requested: composerContext.value.reasoningEffort,
      available: selectedEfforts,
      advertisedDefault: parsed.modelDefaultReasoningEfforts[selected],
    );
    composerContext.value = composerContext.value.copyWith(
      model: selected,
      models: models,
      modelLabels: labels,
      reasoningEffort: selectedEffort,
      reasoningEfforts: selectedEfforts,
      modelReasoningEfforts: parsed.modelReasoningEfforts,
      modelDefaultReasoningEfforts: parsed.modelDefaultReasoningEfforts,
    );

    // A model saved from an older host may no longer exist remotely. Do not
    // keep sending that stale identifier after the real list has arrived.
    if (Get.isRegistered<SettingsPreferencesController>()) {
      final preferences = Get.find<SettingsPreferencesController>();
      final configured = preferences.defaultModel.value;
      if (configured != '自动选择' && !models.contains(configured)) {
        preferences.setDefaultModel('自动选择');
      }
      applyTaskPreferences(preferences);
    }
  }

  void _clearRemoteModels() {
    composerContext.value = composerContext.value.copyWith(
      model: '',
      models: const [],
      modelLabels: const {},
      reasoningEffort: '',
      reasoningEfforts: const [],
      modelReasoningEfforts: const {},
      modelDefaultReasoningEfforts: const {},
    );
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
    _expirePendingCommands();
    if (_coalescesPendingCommand(type) &&
        _pendingCommands.values.any(
          (pending) => pending.matches(type, threadId: threadId),
        )) {
      return;
    }
    final requestId = RelayProtocol.randomId('req');
    _outgoingSequence += 1;
    _pendingCommands[requestId] = _PendingCommand(
      kind: type,
      threadId: threadId,
      sentAt: DateTime.now(),
    );
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

  bool _coalescesPendingCommand(String type) {
    return type == 'thread.list' || type == 'thread.read';
  }

  bool _isTransientSyncError(String message) {
    return message.contains('APP_SERVER_TIMEOUT') ||
        message.contains('APP_SERVER_UNAVAILABLE') ||
        message.contains('项目列表同步超时');
  }

  void _expirePendingCommands() {
    final cutoff = DateTime.now().subtract(_commandTimeout);
    var catalogTimedOut = false;
    _pendingCommands.removeWhere((_, pending) {
      final expired = pending.sentAt.isBefore(cutoff);
      if (expired && pending.kind == 'thread.list') catalogTimedOut = true;
      return expired;
    });
    if (catalogTimedOut && lastError.value.isEmpty) {
      lastError.value = '项目列表同步超时，请确认目标主机在线后重试。';
    }
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

  String _resolveReasoningEffort({
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

  String _dateString(Object? value) {
    if (value is num) {
      final raw = value.toInt();
      final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
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
            .map((item) {
              if (item is String) return item.trim();
              if (item is Map) {
                return _extractText(Map<String, dynamic>.from(item));
              }
              return '';
            })
            .where((item) => item.isNotEmpty)
            .join('\n');
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  TokenUsage? _extractTokenUsage(Map<String, dynamic> map) {
    final candidates = <Object?>[
      map['usage'],
      map['tokenUsage'],
      map['token_usage'],
      map['tokens'],
      map,
    ];
    for (final candidate in candidates) {
      final usage = _tokenUsageFromValue(candidate);
      if (usage != null) return usage;
    }
    return null;
  }

  TokenUsage? _tokenUsageFromValue(Object? value) {
    final map = _asMap(value);
    if (map == null) return null;
    final input = _readIntValue(
      map['inputTokens'] ??
          map['input_tokens'] ??
          map['promptTokens'] ??
          map['prompt_tokens'],
    );
    final output = _readIntValue(
      map['outputTokens'] ??
          map['output_tokens'] ??
          map['completionTokens'] ??
          map['completion_tokens'],
    );
    final total = _readIntValue(
      map['totalTokens'] ?? map['total_tokens'] ?? map['total'],
    );
    if (input == null && output == null && total == null) return null;
    final resolvedInput = input ?? 0;
    final resolvedOutput = output ?? 0;
    return TokenUsage(
      inputTokens: resolvedInput,
      outputTokens: resolvedOutput,
      totalTokens: total ?? resolvedInput + resolvedOutput,
    );
  }

  int? _readIntValue(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  List<EventAttachment> _extractAttachments(Map<String, dynamic> map) {
    final attachments = <EventAttachment>[];
    final seen = <String>{};

    void visit(Object? value, int depth) {
      if (depth > 5) return;
      if (value is Map) {
        final candidate = _attachmentFromMap(Map<String, dynamic>.from(value));
        if (candidate != null) {
          final key = [
            candidate.thumbnailDataUrl,
            candidate.dataUrl,
            candidate.resourceUrl,
          ].join('|');
          if (seen.add(key)) attachments.add(candidate);
        }
        for (final nested in value.values) {
          visit(nested, depth + 1);
        }
      } else if (value is List) {
        for (final nested in value) {
          visit(nested, depth + 1);
        }
      }
    }

    visit(map, 0);
    return attachments;
  }

  EventAttachment? _attachmentFromMap(Map<String, dynamic> map) {
    final nestedImageUrl = _asMap(map['image_url']) ?? _asMap(map['imageUrl']);
    final type =
        (_readString(map['type']) ?? _readString(nestedImageUrl?['type']) ?? '')
            .toLowerCase();
    final mime =
        _readString(map['mime']) ??
        _readString(map['mimeType']) ??
        _readString(map['mediaType']) ??
        _readString(nestedImageUrl?['mime']) ??
        _readString(nestedImageUrl?['mimeType']) ??
        '';
    final isImage =
        type == 'image' ||
        type.contains('image') ||
        mime.toLowerCase().startsWith('image/');
    if (!isImage) return null;

    var dataUrl = _firstString([
      map['dataUrl'],
      map['data_url'],
      map['source'],
      nestedImageUrl?['dataUrl'],
      nestedImageUrl?['data_url'],
    ]);
    final rawData = _firstString([map['data'], nestedImageUrl?['data']]);
    if (dataUrl.isEmpty && rawData.startsWith('data:image/')) {
      dataUrl = rawData;
    } else if (dataUrl.isEmpty &&
        rawData.isNotEmpty &&
        mime.toLowerCase().startsWith('image/') &&
        rawData.length <= 3 * 1024 * 1024) {
      dataUrl = 'data:$mime;base64,$rawData';
    }
    final thumbnailDataUrl = _firstString([
      map['thumbnailDataUrl'],
      map['thumbnail_data_url'],
      map['thumbnail'],
      map['thumb'],
      nestedImageUrl?['thumbnailDataUrl'],
      nestedImageUrl?['thumbnail_data_url'],
      nestedImageUrl?['thumbnail'],
    ]);
    final resourceUrl = _firstString([
      map['resourceUrl'],
      map['resource_url'],
      map['url'],
      nestedImageUrl?['resourceUrl'],
      nestedImageUrl?['resource_url'],
      nestedImageUrl?['url'],
    ]);
    if (dataUrl.isEmpty && thumbnailDataUrl.isEmpty && resourceUrl.isEmpty) {
      return null;
    }
    return EventAttachment(
      type: 'image',
      mime: mime.isEmpty ? 'image/*' : mime,
      dataUrl: dataUrl,
      thumbnailDataUrl: thumbnailDataUrl,
      resourceUrl: resourceUrl,
      expiresAt: _firstString([
        map['expiresAt'],
        map['expires_at'],
        nestedImageUrl?['expiresAt'],
        nestedImageUrl?['expires_at'],
      ]),
    );
  }

  String _firstString(Iterable<Object?> values) {
    for (final value in values) {
      final text = _readString(value);
      if (text != null) return text;
    }
    return '';
  }

  void _handleDone() {
    final wasConnected = connected.value;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    connected.value = false;
    connectionLabel.value = 'offline';
    _clearRemoteModels();
    if (wasConnected &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
    _socket = null;
    _socketSubscription = null;
    _scheduleReconnect();
  }

  void _handleSocketError(Object error) {
    final wasConnected = connected.value;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    connected.value = false;
    connectionLabel.value = 'failed';
    _clearRemoteModels();
    _fail(error);
    if (wasConnected &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
    _scheduleReconnect();
  }

  void _refreshLiveTimeline() {
    if (!connected.value) return;
    _sendCommand('thread.list', {'limit': 100});
    // Only a running turn needs live detail polling. Completed threads are
    // loaded once when selected.
    if (_requestedEventsSessionId != null && timelineSessionRunning.value) {
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
      // A catalog refresh may lag behind the turn.started/turn.completed
      // event stream. Do not interpret a stale done/idle row as completion
      // while the local lifecycle still says this session is running.
      final lifecycle = _sessionLifecycles[session.id.trim()];
      if (lifecycle?.visibleRunning == true ||
          session.id.trim() == currentSessionId.value?.trim() &&
              timelineSessionRunning.value) {
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
    final index = sessions.indexWhere(
      (session) => session.id.trim() == sessionId.trim(),
    );
    if (index < 0 || sessions[index].isRunning) return;
    sessions[index] = sessions[index].copyWith(status: 'running');
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

  void _loadLatestSessionEventsForSelectedWorkspace() {
    if (!connected.value) return;
    if (_pendingSessionStart) return;
    if (sessions.isEmpty) {
      selectedSessionId.value = null;
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
      selectedSessionId.value = null;
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

    final selectedId = selectedSessionId.value;
    // Catalog synchronization should only populate the sidebar. Loading a
    // conversation is an explicit task-selection action; automatically
    // opening the latest completed thread can immediately request tens of
    // megabytes of historical tool output after every app restart.
    if (selectedId == null) {
      currentSessionId.value = null;
      timelineSessionRunning.value = false;
      return;
    }
    final selected = candidates.cast<SessionRecord?>().firstWhere(
      (session) => session?.id == selectedId,
      orElse: () => null,
    );
    if (selected == null) {
      selectedSessionId.value = null;
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      timelineSessionRunning.value = false;
      return;
    }
    final latest = selected;
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

    // A completed thread is loaded once when selected. Re-reading its full
    // history during every 2-second catalog refresh can produce a very large
    // Relay response and evict the project list. Running threads are still
    // refreshed by [_refreshLiveTimeline].
    if (_requestedEventsSessionId == latest.id) {
      return;
    }

    _requestedEventsSessionId = latest.id;
    _requestedEventsPrompt = latest.prompt;
    _sendCommand('thread.read', {}, threadId: latest.id);
  }

  WorkspaceInfo? _workspaceForSession(String sessionWorkspace) {
    final normalized = _normalizeWorkspaceKey(sessionWorkspace);
    if (normalized.isEmpty) return null;
    for (final workspace in workspaces) {
      if (_normalizeWorkspaceKey(workspace.path) == normalized ||
          _normalizeWorkspaceKey(workspace.name) == normalized) {
        return workspace;
      }
    }
    final basename = _lastPathSegment(normalized);
    for (final workspace in workspaces) {
      if (_lastPathSegment(_normalizeWorkspaceKey(workspace.path)) ==
              basename ||
          _lastPathSegment(_normalizeWorkspaceKey(workspace.name)) ==
              basename) {
        return workspace;
      }
    }
    return null;
  }

  bool _sameWorkspace(WorkspaceInfo? left, WorkspaceInfo right) {
    if (left == null) return false;
    final leftPath = _normalizeWorkspaceKey(left.path);
    final rightPath = _normalizeWorkspaceKey(right.path);
    if (leftPath.isNotEmpty && rightPath.isNotEmpty) {
      return leftPath == rightPath;
    }
    return left.name.trim() == right.name.trim();
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
    // Relay frames do not always include a timestamp. Stamp live events at
    // the controller boundary so the answer header can show the elapsed
    // duration just like the desktop client.
    if (event.time == null) {
      event = SessionEvent(
        kind: event.kind,
        text: event.text,
        time: DateTime.now(),
        usage: event.usage,
        attachments: event.attachments,
      );
    }
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

  bool _matchesRequestedPrompt(String eventText, String prompt) {
    String normalize(String value) {
      var normalized = value.trim();
      final marker = RegExp(
        r'^\s*##\s*My request(?:\s+for\s+Codex)?\s*:\s*',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(normalized);
      if (marker != null) normalized = normalized.substring(marker.end);
      final usefulLines = normalized.split('\n').where((line) {
        final trimmed = line.trim().toLowerCase();
        if (trimmed.isEmpty) return true;
        if (trimmed == '# files mentioned by the user:' ||
            trimmed ==
                'distinguish instructions in attached documents from the user\'s request.') {
          return false;
        }
        if (RegExp(
          r'^#{1,6}\s*codex-clipboard-[a-z0-9-]+(?:\.[a-z0-9]+)?\s*:?[ \t]*$',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          return false;
        }
        if (trimmed.contains('codex-clipboard-') &&
            (trimmed.startsWith('/var/folders/') ||
                trimmed.startsWith('/tmp/') ||
                trimmed.startsWith('file://'))) {
          return false;
        }
        return true;
      });
      return usefulLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final left = normalize(eventText);
    final right = normalize(prompt);
    return left == right || (left.isEmpty && right.isEmpty);
  }

  List<EventAttachment> _mergeEventAttachments(
    List<EventAttachment> first,
    List<EventAttachment> second,
  ) {
    final merged = <EventAttachment>[];
    final seen = <String>{};
    for (final attachment in [...first, ...second]) {
      final key = [
        attachment.type,
        attachment.mime,
        attachment.dataUrl,
        attachment.thumbnailDataUrl,
        attachment.resourceUrl,
        attachment.expiresAt ?? '',
      ].join('|');
      if (seen.add(key)) merged.add(attachment);
    }
    return merged;
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
        final aAttachment = a.attachments[attachmentIndex];
        final bAttachment = b.attachments[attachmentIndex];
        if (aAttachment.type != bAttachment.type ||
            aAttachment.mime != bAttachment.mime ||
            aAttachment.dataUrl != bAttachment.dataUrl ||
            aAttachment.thumbnailDataUrl != bAttachment.thumbnailDataUrl ||
            aAttachment.resourceUrl != bAttachment.resourceUrl ||
            aAttachment.expiresAt != bAttachment.expiresAt) {
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
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : null;
    if (preferences != null) await preferences.ready;
    try {
      await initializeStorage();
      final storedValue = _storage.read<dynamic>(_pairingsStorageKey);
      List<PairingProfile> restored = const [];
      if (storedValue != null) {
        try {
          final decoded = storedValue is String
              ? jsonDecode(storedValue)
              : storedValue;
          if (decoded is List) {
            restored = decoded
                .whereType<Map>()
                .map(
                  (item) =>
                      PairingProfile.fromJson(Map<String, dynamic>.from(item)),
                )
                .where((profile) => profile.id.isNotEmpty)
                .toList();
          }
        } catch (_) {
          restored = const [];
        }
      }

      // An existing empty list is an intentional "no pairings" state. Only
      // migrate from Keychain when the new local container has no value yet.
      if (restored.isEmpty && storedValue == null) {
        restored = await _readLegacyPairings();
        if (restored.isNotEmpty) {
          pairings.assignAll(restored);
          final storedActiveId = await _legacySecureStorage.read(
            key: _activePairingStorageKey,
          );
          final selected = restored.firstWhere(
            (profile) => profile.id == storedActiveId,
            orElse: () => restored.first,
          );
          activePairingId.value = selected.id;
          await _persistActivePairingId();
          await _persistPairings();
        } else {
          final legacy = await _readLegacyPairing();
          if (legacy != null) {
            restored = [legacy];
            pairings.assignAll(restored);
            activePairingId.value = legacy.id;
            await _persistActivePairingId();
            await _persistPairings();
          }
        }
      } else if (restored.isNotEmpty) {
        pairings.assignAll(restored);
        final storedActiveId = _storage.read<String>(_activePairingStorageKey);
        final selected = restored.firstWhere(
          (profile) => profile.id == storedActiveId,
          orElse: () => restored.first,
        );
        activePairingId.value = selected.id;
        await _persistActivePairingId();
      } else {
        pairings.clear();
        activePairingId.value = null;
      }

      final selectedProfile = activePairing;
      if (selectedProfile != null) {
        await _applyPairing(selectedProfile);
        shouldAutoConnect =
            selectedProfile.isComplete &&
            (preferences?.autoConnect.value ?? true);
      } else {
        deviceId.value = _newDeviceId();
      }
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

  Future<void> _applySavedTaskPreferences() async {
    if (!Get.isRegistered<SettingsPreferencesController>()) return;
    final preferences = Get.find<SettingsPreferencesController>();
    await preferences.ready;
    applyTaskPreferences(preferences);
  }

  String _approvalPolicyFor(String mode) {
    return switch (mode) {
      '完全访问权限' => 'never',
      '自动审查' => 'on-failure',
      _ => 'on-request',
    };
  }

  Future<PairingProfile?> _readLegacyPairing() async {
    final storedBaseUrl = await _legacySecureStorage.read(
      key: 'recodex_base_url',
    );
    final storedSpaceId = await _legacySecureStorage.read(
      key: 'recodex_space_id',
    );
    final storedTargetDeviceId = await _legacySecureStorage.read(
      key: 'recodex_target_device_id',
    );
    final storedDeviceName = await _legacySecureStorage.read(
      key: 'recodex_device_name',
    );
    final storedDeviceId = await _legacySecureStorage.read(
      key: 'recodex_device_id',
    );
    final storedDeviceKey = await _legacySecureStorage.read(
      key: 'recodex_endpoint_private_key',
    );
    final storedPairingToken = await _legacySecureStorage.read(
      key: 'recodex_pairing_token',
    );
    final storedEndpointGrant = await _legacySecureStorage.read(
      key: 'recodex_endpoint_grant',
    );
    final storedTokenExpiresAt = await _legacySecureStorage.read(
      key: 'recodex_token_expires_at',
    );
    final storedGrantExpiresAt = await _legacySecureStorage.read(
      key: 'recodex_grant_expires_at',
    );
    final storedWorkspaceName = await _legacySecureStorage.read(
      key: 'recodex_selected_workspace_name',
    );
    final storedWorkspacePath = await _legacySecureStorage.read(
      key: 'recodex_selected_workspace_path',
    );
    final hasLegacyData = [
      storedSpaceId,
      storedTargetDeviceId,
      storedPairingToken,
      storedEndpointGrant,
    ].any((value) => value != null && value.trim().isNotEmpty);
    if (!hasLegacyData) return null;
    return PairingProfile(
      id: 'pairing_legacy',
      name: '默认配对',
      baseUrl: _normalizeRelayUrl(
        storedBaseUrl ?? 'ws://127.0.0.1:8788/v1/connect',
      ),
      spaceId: storedSpaceId?.trim() ?? '',
      deviceName: storedDeviceName?.trim().isNotEmpty == true
          ? storedDeviceName!.trim()
          : 'Flutter phone',
      deviceId: storedDeviceId?.trim().isNotEmpty == true
          ? storedDeviceId!.trim()
          : _newDeviceId(),
      targetDeviceId: storedTargetDeviceId?.trim() ?? '',
      endpointType: 'app',
      deviceKey: storedDeviceKey?.trim() ?? '',
      endpointPublicKey: '',
      pairingToken: storedPairingToken?.trim() ?? '',
      endpointGrant: storedEndpointGrant?.trim() ?? '',
      tokenExpiresAt: int.tryParse(storedTokenExpiresAt ?? '') ?? 0,
      grantExpiresAt: int.tryParse(storedGrantExpiresAt ?? '') ?? 0,
      selectedWorkspaceName: storedWorkspaceName,
      selectedWorkspacePath: storedWorkspacePath,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<List<PairingProfile>> _readLegacyPairings() async {
    try {
      final encoded = await _legacySecureStorage.read(key: _pairingsStorageKey);
      if (encoded == null || encoded.trim().isEmpty) return const [];
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => PairingProfile.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((profile) => profile.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
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
      await initializeStorage();
      await _storage.write('recodex_endpoint_private_key', deviceKey.value);
    } catch (_) {
      // Keep the key in memory when local storage is unavailable.
    }
    return pair;
  }

  String _newDeviceId() {
    return 'flutter_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _storeConnectionHints() async {
    try {
      await initializeStorage();
      final current = activePairing;
      if (current != null) {
        final index = pairings.indexWhere(
          (profile) => profile.id == current.id,
        );
        if (index >= 0) {
          pairings[index] = _profileFromState(
            name: current.name,
            id: current.id,
          );
        }
        await _persistPairings();
      }
      await _storage.write('recodex_base_url', baseUrl.value);
      await _storage.write('recodex_space_id', spaceId.value);
      await _storage.write('recodex_target_device_id', targetDeviceId.value);
      await _storage.write('recodex_device_name', deviceName.value);
      await _storage.write('recodex_device_id', deviceId.value);
      await _storage.write('recodex_endpoint_private_key', deviceKey.value);
      await _writeOrRemove('recodex_pairing_token', pairingToken.value);
      await _writeOrRemove('recodex_endpoint_grant', endpointGrant.value);
      await _storage.write('recodex_token_expires_at', tokenExpiresAt.value);
      await _storage.write('recodex_grant_expires_at', grantExpiresAt.value);
    } catch (_) {
      // Keep the in-memory values for the current connection if storage is unavailable.
    }
  }

  Future<void> _writeOrRemove(String key, String value) async {
    if (value.isEmpty) {
      await _storage.remove(key);
    } else {
      await _storage.write(key, value);
    }
  }

  WorkspaceInfo? _restoreSelectedWorkspace() {
    if (workspaces.isEmpty) return null;
    final defaultWorkspacePath =
        Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>().defaultWorkspacePath.value
        : '';
    if (defaultWorkspacePath.trim().isNotEmpty) {
      for (final workspace in workspaces) {
        if (workspace.path == defaultWorkspacePath) return workspace;
      }
    }
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
      await initializeStorage();
      if (workspace == null) {
        _storedWorkspaceName = null;
        _storedWorkspacePath = null;
        await _storage.remove('recodex_selected_workspace_name');
        await _storage.remove('recodex_selected_workspace_path');
        final current = activePairing;
        if (current != null) {
          final index = pairings.indexWhere(
            (profile) => profile.id == current.id,
          );
          if (index >= 0) {
            pairings[index] = current.copyWith(
              clearSelectedWorkspace: true,
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            );
          }
          await _persistPairings();
        }
        return;
      }
      _storedWorkspaceName = workspace.name;
      _storedWorkspacePath = workspace.path;
      await _storage.write('recodex_selected_workspace_name', workspace.name);
      await _storage.write('recodex_selected_workspace_path', workspace.path);
      final current = activePairing;
      if (current != null) {
        final index = pairings.indexWhere(
          (profile) => profile.id == current.id,
        );
        if (index >= 0) {
          pairings[index] = current.copyWith(
            selectedWorkspaceName: workspace.name,
            selectedWorkspacePath: workspace.path,
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          );
        }
        await _persistPairings();
      }
    } catch (_) {
      // Keep the in-memory selection for this run if secure storage is unavailable.
    }
  }

  Future<void> _storeSelectedSession(String? sessionId) async {
    final normalized = sessionId?.trim() ?? '';
    _storedSessionId = normalized.isEmpty ? null : normalized;
    try {
      await initializeStorage();
      final current = activePairing;
      if (current == null) return;
      final index = pairings.indexWhere((profile) => profile.id == current.id);
      if (index < 0) return;
      pairings[index] = current.copyWith(
        selectedSessionId: _storedSessionId,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await _persistPairings();
    } catch (_) {
      // Keep the in-memory selection for this run if local storage is unavailable.
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
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : null;
    if (_manualDisconnect ||
        preferences != null && !preferences.autoReconnect.value ||
        (pairingToken.value.isEmpty && endpointGrant.value.isEmpty) ||
        spaceId.value.isEmpty ||
        targetDeviceId.value.isEmpty ||
        _reconnectTimer != null) {
      return;
    }
    connectionLabel.value = 'reconnecting';
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      final currentPreferences =
          Get.isRegistered<SettingsPreferencesController>()
          ? Get.find<SettingsPreferencesController>()
          : null;
      if (!_manualDisconnect &&
          !connected.value &&
          (currentPreferences?.autoReconnect.value ?? true) &&
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
      throw StateError('缺少连接令牌');
    }
    return pairingToken.value;
  }

  Future<void> _refreshConnectToken() async {
    if (_keyPair == null || endpointGrant.value.isEmpty) {
      throw StateError('缺少接入端授权凭证或接入端私钥');
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
      throw FormatException('Relay 连接地址必须是无 query/hash 的 WebSocket 地址');
    }
    final normalized = uri.path.isEmpty || uri.path == '/'
        ? uri.replace(path: '/v1/connect')
        : uri;
    if (normalized.path != '/v1/connect') {
      throw FormatException('Relay 连接地址必须使用 /v1/connect');
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
  const _PendingCommand({
    required this.kind,
    required this.sentAt,
    this.threadId,
  });

  final String kind;
  final String? threadId;
  final DateTime sentAt;

  bool matches(String commandKind, {String? threadId}) {
    return kind == commandKind && this.threadId == threadId;
  }
}
