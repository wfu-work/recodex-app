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

  /// Canonical state for the selected timeline. [timelineSessionRunning] is
  /// retained as a compatibility flag for the composer and older widgets,
  /// while this value carries waiting/terminal states as well.
  final timelineStatus = TimelineTaskStatus.unknown.obs;
  final timelineActiveFlags = <String>[].obs;
  final timelineTurnStartedAt = Rxn<DateTime>();
  final timelineClock = 0.obs;
  final timelineSessionRunning = false.obs;
  final timelineRevision = 0.obs;

  /// State for the one-off `thread.read` that hydrates the selected task.
  /// Keeping this separate from [lastError] lets the conversation view show
  /// useful recovery details without turning every remote error into a
  /// global banner.
  final timelineLoading = false.obs;
  final timelineLoadError = ''.obs;
  final timelineLoadElapsedSeconds = 0.obs;

  /// Whether the user-triggered catalog/timeline refresh is waiting for a
  /// response. This is separate from [timelineLoading], which only covers
  /// the first hydration of the selected conversation.
  final timelineRefreshing = false.obs;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _liveTimelineTimer;
  Timer? _handshakeTimer;
  Timer? _heartbeatTimer;
  Timer? _healthCheckTimer;
  Timer? _timelineLoadTimer;
  Timer? _timelineLoadTimeoutTimer;
  Timer? _timelineStatusTimer;
  Timer? _timelineRefreshTimeoutTimer;
  int _outgoingSequence = 0;
  int _lastIncomingSequence = 0;
  int _maxFrameSize = RelayProtocol.defaultMaxFrameSize;
  bool _manualDisconnect = false;
  bool _hadOnlineConnection = false;
  bool _pendingSessionStart = false;
  bool _interruptRequested = false;
  String? _pendingPrompt;
  String? _currentTurnId;
  String? _lastTerminalTurnId;
  DateTime? _currentTurnStartedAt;
  String? _pendingHelloRequestId;
  SimpleKeyPair? _keyPair;
  bool _forceTokenRefresh = false;
  final _pendingCommands = <String, _PendingCommand>{};
  final _seenIncomingMessageIds = <String>{};
  Completer<String?>? _healthCheckCompleter;
  final _credentialsLoaded = Completer<void>();
  String? _requestedEventsSessionId;
  String? _requestedEventsPrompt;
  String? _storedWorkspaceName;
  String? _storedWorkspacePath;
  String? _storedSessionId;
  String? _timelineLoadingSessionId;
  DateTime? _timelineLoadStartedAt;
  int _timelineRefreshToken = 0;
  int? _activeTimelineRefreshToken;
  // Monotonically identifies the latest thread.read request.  A read can
  // outlive a task selection (or a forced refresh) on the Relay, so its
  // response must never be allowed to hydrate a newer timeline.
  int _timelineReadGeneration = 0;
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
    _timelineStatusTimer?.cancel();
    _timelineStatusTimer = null;
    _finishTimelineRefresh();
    _clearTimelineLoadState();
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
    _finishTimelineRefresh();
    _clearTimelineLoadState();
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
    _setTimelineStatus(TimelineTaskStatus.unknown);
    timelineRevision.value += 1;
    relaySessionId.value = '';
    _outgoingSequence = 0;
    _lastIncomingSequence = 0;
    _pendingSessionStart = false;
    _interruptRequested = false;
    _pendingPrompt = null;
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _currentTurnStartedAt = null;
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
      _fail(_connectionTestError(error));
      connectionLabel.value = 'failed';
      connected.value = false;
      _scheduleReconnect();
    } finally {
      busy.value = false;
    }
  }

  /// Checks a Relay pairing without changing the active profile. An exact
  /// match for the authenticated connection is verified with a ping; drafts
  /// that differ from it use a short-lived handshake so users can verify
  /// endpoint credentials before saving them.
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

      // The active connection already authenticated this exact pairing. Do
      // not consume another Relay connection slot just to test it again.
      // Drafts that differ from the active connection still use the isolated
      // handshake below so the editor can validate unsaved credentials.
      if (_canReuseActiveConnection(
        normalizedBaseUrl: normalizedBaseUrl,
        token: connectToken,
        spaceId: nextSpaceId,
        targetDeviceId: nextTargetDeviceId,
        endpointId: nextEndpointId,
        endpointType: nextEndpointType,
        deviceKey: encodedKey,
      )) {
        return checkCurrentConnection();
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
              complete(_friendlyRelayError(code, message));
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
            complete(_connectionTestError(error));
          }
        },
        onError: (Object error) => complete(_connectionTestError(error)),
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
      return _connectionTestError(error);
    } finally {
      timeout?.cancel();
      await subscription?.cancel();
      await socket?.close();
    }
  }

  /// Checks the already authenticated WebSocket with an application-level
  /// ping. This keeps the connection limit at one while still verifying that
  /// Relay is responding to the current connection.
  Future<String?> checkCurrentConnection() async {
    final socket = _socket;
    if (!connected.value ||
        socket == null ||
        socket.readyState != WebSocket.open) {
      return '当前 Relay 未连接，请先连接后再测试。';
    }

    final pending = _healthCheckCompleter;
    if (pending != null) return pending.future;

    final completer = Completer<String?>();
    _healthCheckCompleter = completer;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer(const Duration(seconds: 5), () {
      _finishHealthCheck('当前 Relay 连接无响应，请检查网络后重试。');
    });
    if (!_sendRaw(RelayProtocol.ping())) {
      _finishHealthCheck('当前 Relay 连接不可用，请重新连接后再试。');
    }
    return completer.future;
  }

  bool _canReuseActiveConnection({
    required String normalizedBaseUrl,
    required String token,
    required String spaceId,
    required String targetDeviceId,
    required String endpointId,
    required String endpointType,
    required String deviceKey,
  }) {
    final socket = _socket;
    return connected.value &&
        socket != null &&
        socket.readyState == WebSocket.open &&
        normalizedBaseUrl == baseUrl.value &&
        token == pairingToken.value &&
        spaceId == this.spaceId.value &&
        targetDeviceId == this.targetDeviceId.value &&
        endpointId == deviceId.value &&
        endpointType == this.endpointType.value &&
        deviceKey == this.deviceKey.value;
  }

  void _finishHealthCheck(String? error) {
    final completer = _healthCheckCompleter;
    if (completer == null) return;
    _healthCheckCompleter = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    if (!completer.isCompleted) completer.complete(error);
  }

  Future<void> disconnect({bool silent = false}) async {
    _manualDisconnect = true;
    _finishTimelineRefresh();
    _clearTimelineLoadState();
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    _reconnectTimer?.cancel();
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _finishHealthCheck('Relay 连接已断开。');
    await _closeSocket();
    connected.value = false;
    connectionLabel.value = 'offline';
    _clearRemoteModels();
    _hadOnlineConnection = false;
  }

  /// Starts the selected task hydration clock. A task read is deliberately
  /// bounded so a Relay or host that never answers cannot leave the UI in an
  /// indeterminate loading state forever.
  void _beginTimelineLoad(String sessionId) {
    final normalizedId = sessionId.trim();
    if (normalizedId.isEmpty) return;
    _timelineLoadTimer?.cancel();
    _timelineLoadTimeoutTimer?.cancel();
    _timelineLoadingSessionId = normalizedId;
    _timelineLoadStartedAt = DateTime.now();
    timelineLoading.value = true;
    timelineLoadError.value = '';
    timelineLoadElapsedSeconds.value = 0;
    _timelineLoadTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _timelineLoadStartedAt;
      if (!timelineLoading.value ||
          _timelineLoadingSessionId != normalizedId ||
          startedAt == null) {
        return;
      }
      timelineLoadElapsedSeconds.value = DateTime.now()
          .difference(startedAt)
          .inSeconds;
    });
    _timelineLoadTimeoutTimer = Timer(_commandTimeout, () {
      if (!timelineLoading.value || _timelineLoadingSessionId != normalizedId) {
        return;
      }
      _pendingCommands.removeWhere(
        (_, pending) =>
            pending.kind == 'thread.read' && pending.threadId == normalizedId,
      );
      _failTimelineLoad(
        '任务对话加载超时（已等待 ${_commandTimeout.inSeconds} 秒），请检查 Relay 或目标主机后重试。',
        sessionId: normalizedId,
      );
    });
  }

  void _finishTimelineLoad({String? sessionId}) {
    if (sessionId != null && sessionId != _timelineLoadingSessionId) return;
    _timelineLoadTimer?.cancel();
    _timelineLoadTimeoutTimer?.cancel();
    _timelineLoadTimer = null;
    _timelineLoadTimeoutTimer = null;
    _timelineLoadingSessionId = null;
    _timelineLoadStartedAt = null;
    timelineLoading.value = false;
    timelineLoadError.value = '';
    timelineLoadElapsedSeconds.value = 0;
  }

  void _failTimelineLoad(String message, {String? sessionId}) {
    if (sessionId != null && sessionId != _timelineLoadingSessionId) return;
    _timelineLoadTimer?.cancel();
    _timelineLoadTimeoutTimer?.cancel();
    _timelineLoadTimer = null;
    _timelineLoadTimeoutTimer = null;
    _timelineLoadingSessionId = null;
    _timelineLoadStartedAt = null;
    timelineLoading.value = false;
    timelineLoadError.value = message;
  }

  void _clearTimelineLoadState() {
    final invalidatedThreadIds = <String>{};
    final loadingThreadId = _timelineLoadingSessionId;
    if (loadingThreadId != null && loadingThreadId.isNotEmpty) {
      invalidatedThreadIds.add(loadingThreadId);
    }
    final selectedThreadId = selectedSessionId.value?.trim();
    if (selectedThreadId != null && selectedThreadId.isNotEmpty) {
      invalidatedThreadIds.add(selectedThreadId);
    }
    if (invalidatedThreadIds.isNotEmpty) {
      _pendingCommands.removeWhere(
        (_, pending) =>
            pending.kind == 'thread.read' &&
            invalidatedThreadIds.contains(pending.threadId?.trim()),
      );
    }
    _timelineLoadTimer?.cancel();
    _timelineLoadTimeoutTimer?.cancel();
    _timelineLoadTimer = null;
    _timelineLoadTimeoutTimer = null;
    _timelineLoadingSessionId = null;
    _timelineLoadStartedAt = null;
    timelineLoading.value = false;
    timelineLoadError.value = '';
    timelineLoadElapsedSeconds.value = 0;
    // Invalidating the generation here also invalidates any in-flight read
    // that may return after the user switched task/project or disconnected.
    _timelineReadGeneration += 1;
  }

  void _beginTimelineRefresh() {
    _timelineRefreshTimeoutTimer?.cancel();
    final token = ++_timelineRefreshToken;
    _activeTimelineRefreshToken = token;
    timelineRefreshing.value = true;
    if (lastError.value.startsWith('任务刷新')) lastError.value = '';
    _timelineRefreshTimeoutTimer = Timer(_commandTimeout, () {
      if (_activeTimelineRefreshToken != token) return;
      _finishTimelineRefresh(error: '任务刷新超时，请确认目标主机在线后重试。');
    });
  }

  void _finishTimelineRefresh({String? error, int? token}) {
    if (token != null && token != _activeTimelineRefreshToken) return;
    final hadActiveRefresh = _activeTimelineRefreshToken != null;
    _timelineRefreshTimeoutTimer?.cancel();
    _timelineRefreshTimeoutTimer = null;
    _activeTimelineRefreshToken = null;
    timelineRefreshing.value = false;
    if (hadActiveRefresh && error != null && error.isNotEmpty) {
      lastError.value = error;
    }
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
    _finishTimelineRefresh();
    _finishHealthCheck('Relay 连接已断开。');
    _currentTurnStartedAt = null;
    await subscription?.cancel();
    if (socket != null) {
      await socket.close();
    }
  }

  void selectWorkspace(WorkspaceInfo? workspace) {
    _clearTimelineLoadState();
    selectedWorkspace.value = workspace;
    unawaited(_storeSelectedWorkspace(workspace));
    gitSnapshot.value = null;
    currentSessionId.value = null;
    selectedSessionId.value = null;
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    // An explicit project switch is a user choice. Do not immediately
    // replace it with the previously opened task while the new catalog is
    // synchronizing.
    _sessionRestoreAttempted = true;
    _setTimelineStatus(TimelineTaskStatus.unknown);
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

    _clearTimelineLoadState();

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
    // A selected task may have a different latest turn than the task that was
    // visible before it. Do not let a delayed terminal event from the old
    // task pass the turn guard while the new thread.read is in flight.
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _currentTurnStartedAt = null;
    _sessionRestoreAttempted = true;
    _storedSessionId = session.id;
    unawaited(_storeSelectedSession(session.id));
    timelineTurnStartedAt.value = null;
    _setTimelineStatus(
      session.isRunning
          ? TimelineTaskStatus.processing
          : TimelineTaskStatus.loading,
    );
    if (session.isRunning) {
      _markSessionRunningForNotification(session.id);
    }
    _requestedEventsSessionId = session.id;
    _requestedEventsPrompt = session.prompt;
    events.clear();
    _bumpTimelineRevision();
    _beginTimelineLoad(session.id);

    if (!connected.value) {
      _failTimelineLoad('尚未连接 Relay，无法加载任务对话，请连接后重试。');
      return;
    }
    // Selection invalidates the previous read generation. Force a fresh
    // request even when the same thread already has a poll in flight; the
    // old response is intentionally ignored by the generation guard below.
    _sendCommand('thread.read', {}, threadId: session.id, force: true);
  }

  /// Retries hydration for the task currently shown in the conversation
  /// view. This intentionally reuses the same task metadata rather than
  /// selecting a different task as a side effect of a catalog refresh.
  void retrySelectedSession() {
    final selectedId = selectedSessionId.value?.trim() ?? '';
    if (selectedId.isEmpty) return;
    SessionRecord? selected;
    for (final session in sessions) {
      if (session.id.trim() == selectedId) {
        selected = session;
        break;
      }
    }
    _clearTimelineLoadState();
    _requestedEventsSessionId = selectedId;
    _requestedEventsPrompt = selected?.prompt;
    currentSessionId.value = selectedId;
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    timelineTurnStartedAt.value = null;
    _setTimelineStatus(
      selected?.isRunning == true
          ? TimelineTaskStatus.processing
          : TimelineTaskStatus.loading,
    );
    if (selected?.isRunning == true) {
      _markSessionRunningForNotification(selectedId);
    }
    events.clear();
    _bumpTimelineRevision();
    _beginTimelineLoad(selectedId);
    if (!connected.value) {
      _failTimelineLoad('尚未连接 Relay，无法加载任务对话，请连接后重试。');
      return;
    }
    _sendCommand('thread.read', {}, threadId: selectedId, force: true);
  }

  /// Clears the visible transcript so the composer can start a fresh task.
  ///
  /// The last persisted task is intentionally kept in [_storedSessionId];
  /// that value is used to restore the previous task after a Relay reconnect.
  void startNewConversation() {
    _clearTimelineLoadState();
    currentSessionId.value = null;
    selectedSessionId.value = null;
    _setTimelineStatus(TimelineTaskStatus.unknown);
    _pendingSessionStart = false;
    _interruptRequested = false;
    _pendingPrompt = null;
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _currentTurnStartedAt = null;
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
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _currentTurnStartedAt = null;
    _setTimelineStatus(TimelineTaskStatus.processing);
    _interruptRequested = false;
    _pendingSessionStart = true;
    _pendingPrompt = trimmedPrompt;
    timelineTurnStartedAt.value = null;
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
      _currentTurnStartedAt = null;
      _interruptRequested = false;
      _setTimelineStatus(TimelineTaskStatus.interrupted);
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
    if (!connected.value) return;
    _beginTimelineRefresh();
    _refreshLiveTimeline(
      force: true,
      refreshToken: _activeTimelineRefreshToken,
    );
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
    _sendCommand('thread.list', {'limit': 100}, force: true);
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
      if (type == 'pong') {
        _finishHealthCheck(null);
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
      _fail(_connectionTestError(error));
    }
  }

  Map<String, dynamic> _decodeTextMessage(dynamic raw) {
    // `web_socket_channel` normally delivers text frames as String, but a
    // proxy may preserve the frame as Uint8List.  Decode that representation
    // too; otherwise every streamed event is rejected before it reaches the
    // timeline while the socket itself still appears connected.
    final text = raw is String
        ? raw
        : raw is List<int>
        ? utf8.decode(raw, allowMalformed: false)
        : (throw FormatException('Relay 只接受 JSON 文本帧'));
    final decoded = jsonDecode(text);
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
    _finishTimelineRefresh(
      error: '任务刷新失败：${message['message'] ?? 'Relay 返回错误'}',
    );
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final code = message['code'] as String? ?? 'relay.error';
    final text = message['message'] as String? ?? 'Relay 连接被拒绝';
    lastError.value = _friendlyRelayError(code, text);
    _finishHealthCheck(lastError.value);
    if (timelineLoading.value) {
      _failTimelineLoad(
        'Relay 返回错误，任务对话加载失败：${_friendlyRelayError(code, text)}',
      );
    }
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
      if (pending?.refreshToken != null) {
        _finishTimelineRefresh(
          error: '任务刷新失败：$text',
          token: pending!.refreshToken,
        );
      }
      if (pending?.kind == 'thread.read') {
        _failTimelineLoad('任务对话加载失败：$text');
      } else {
        lastError.value = '${errorMap['code'] ?? 'remote.error'}：$text';
      }
      final failedTurnStartBelongsToCurrent =
          pending?.kind == 'turn.start' &&
          pending?.threadId?.trim() == currentSessionId.value?.trim();
      if (pending?.kind == 'thread.create' || failedTurnStartBelongsToCurrent) {
        _finishCurrentSession(
          status: TaskNotificationStatus.failed,
          sessionId: pending?.threadId,
          message: text,
        );
      }
      return;
    }
    if (pending?.refreshToken != null) {
      // The list and read requests are issued together. Either authoritative
      // response is enough to confirm that the manual refresh reached the
      // host; the normal timeline/event flow continues independently.
      _finishTimelineRefresh(token: pending!.refreshToken);
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
        _handleThreadReadResult(
          result,
          readGeneration: pending?.timelineReadGeneration,
        );
      case 'turn.start':
        final startThreadId = pending?.threadId?.trim();
        if (startThreadId != null &&
            startThreadId.isNotEmpty &&
            startThreadId != currentSessionId.value?.trim()) {
          break;
        }
        final map = _asMap(result);
        final startedTurnId =
            _readString(map?['turnId']) ??
            _readString(_asMap(map?['turn'])?['id']);
        if (startedTurnId != null && startedTurnId.isNotEmpty) {
          _currentTurnId = startedTurnId;
          _lastTerminalTurnId = null;
        }
        _sendRequestedInterrupt();
      case 'turn.interrupt':
        final interruptThreadId = pending?.threadId?.trim();
        final interruptTurnId = pending?.turnId?.trim();
        final currentThreadId = currentSessionId.value?.trim();
        final activeTurnId = _currentTurnId?.trim();
        if (pending == null ||
            interruptThreadId == null ||
            interruptThreadId.isEmpty ||
            currentThreadId == null ||
            currentThreadId != interruptThreadId ||
            interruptTurnId == null ||
            interruptTurnId.isEmpty ||
            activeTurnId == null ||
            activeTurnId != interruptTurnId) {
          // The response can arrive after a newer turn has started (or after
          // its interruption event already finalized the session). In either
          // case this command result is stale and must not change the current
          // timeline state.
          break;
        }
        _finishCurrentSession(
          status: TaskNotificationStatus.interrupted,
          sessionId: interruptThreadId,
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
        timelineStatus.value.isActive;
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
    timelineTurnStartedAt.value = null;
    _setTimelineStatus(
      selected.isRunning
          ? TimelineTaskStatus.processing
          : TimelineTaskStatus.loading,
    );
    if (selected.isRunning) {
      _markSessionRunningForNotification(selected.id);
    }
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
        _readString(thread['thread_id']) ??
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
      _readString(thread['cwd_path']),
      _readString(thread['workingDirectory']),
      _readString(thread['workspacePath']),
      _readString(thread['workspace_path']),
      _readString(thread['projectPath']),
      _readString(thread['project_path']),
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
    if (_readBool(thread['active']) ||
        _readBool(thread['running']) ||
        _readBool(thread['isRunning']) ||
        _readBool(thread['is_running'])) {
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
      'systemerror' || 'system_error' => 'error',
      'failed' => 'error',
      'aborted' || 'cancelled' || 'canceled' => 'interrupted',
      _ => normalized,
    };
  }

  bool _readBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  /// Updates the selected timeline from one authoritative lifecycle value.
  ///
  /// App Server notifications can be dropped while the phone reconnects, so
  /// this method is intentionally usable from both notifications and a
  /// `thread.read` snapshot. In particular, an unknown state never implies
  /// completion; it leaves the UI in a recoverable synchronizing state.
  void _setTimelineStatus(
    TimelineTaskStatus status, {
    DateTime? startedAt,
    Iterable<String>? activeFlags,
  }) {
    timelineStatus.value = status;
    timelineActiveFlags.assignAll(activeFlags ?? const <String>[]);
    timelineSessionRunning.value = status.isActive;
    if (status.isActive) {
      if (startedAt != null) timelineTurnStartedAt.value = startedAt;
      _timelineStatusTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        timelineClock.value += 1;
      });
    } else {
      timelineTurnStartedAt.value = null;
      _timelineStatusTimer?.cancel();
      _timelineStatusTimer = null;
    }
  }

  TimelineTaskStatus _timelineStatusFromValue(Object? value) {
    final normalized = (value?.toString().trim().toLowerCase() ?? '')
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
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
      'working' => TimelineTaskStatus.processing,
      'waitingonapproval' ||
      'waiting_on_approval' ||
      'approval' ||
      'approval_requested' ||
      'awaiting_approval' => TimelineTaskStatus.waitingApproval,
      'waitingonuserinput' ||
      'waiting_on_user_input' ||
      'user_input' ||
      'awaiting_user_input' => TimelineTaskStatus.waitingUserInput,
      'completed' ||
      'complete' ||
      'done' ||
      'idle' => TimelineTaskStatus.completed,
      'failed' ||
      'error' ||
      'systemerror' ||
      'system_error' => TimelineTaskStatus.failed,
      'interrupted' ||
      'aborted' ||
      'cancelled' ||
      'canceled' => TimelineTaskStatus.interrupted,
      _ => TimelineTaskStatus.unknown,
    };
  }

  TimelineTaskStatus _timelineStatusFromTurn(Map<String, dynamic> turn) {
    final status =
        turn['status'] ??
        turn['state'] ??
        turn['turnStatus'] ??
        turn['turn_status'];
    final raw = status is Map
        ? (_readString(status['type']) ??
              _readString(status['state']) ??
              _readString(status['status']))
        : _readString(status);
    final parsed = _timelineStatusFromValue(raw);
    if (parsed != TimelineTaskStatus.unknown) return parsed;
    // Older App Server snapshots omitted `status` but retained turn timing.
    // A started turn with no completion timestamp is still active; a
    // completion timestamp is enough to establish a terminal turn.
    final startedAt = _turnTimestamp(turn, 'startedAt');
    final completedAt = _turnTimestamp(turn, 'completedAt');
    if (startedAt != null && completedAt == null) {
      return TimelineTaskStatus.processing;
    }
    if (completedAt != null || _turnDurationMs(turn) != null) {
      return TimelineTaskStatus.completed;
    }
    return TimelineTaskStatus.unknown;
  }

  List<String> _threadActiveFlags(Map<String, dynamic> thread) {
    final status = _asMap(thread['status']);
    final raw =
        status?['activeFlags'] ??
        status?['active_flags'] ??
        thread['activeFlags'] ??
        thread['active_flags'];
    return _asList(raw)
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  TimelineTaskStatus _timelineStatusFromThread(Map<String, dynamic> thread) {
    // A few relay/app-server versions mirror the active state as a boolean
    // while the structured `status` field is still catching up.  Treat that
    // positive signal as authoritative; an idle/aborted value from the same
    // patch is then known to be stale rather than a real completion.
    if (_readBool(thread['active']) ||
        _readBool(thread['running']) ||
        _readBool(thread['isRunning']) ||
        _readBool(thread['is_running'])) {
      return TimelineTaskStatus.processing;
    }
    final flags = _threadActiveFlags(thread)
        .map(
          (value) =>
              value.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_'),
        )
        .toSet();
    if (flags.contains('waitingonapproval') ||
        flags.contains('waiting_on_approval')) {
      return TimelineTaskStatus.waitingApproval;
    }
    if (flags.contains('waitingonuserinput') ||
        flags.contains('waiting_on_user_input')) {
      return TimelineTaskStatus.waitingUserInput;
    }
    final status = thread['status'];
    if (status is Map) {
      final parsed = _timelineStatusFromValue(
        _readString(status['type']) ??
            _readString(status['state']) ??
            _readString(status['status']),
      );
      if (parsed != TimelineTaskStatus.unknown) return parsed;
    } else {
      final parsed = _timelineStatusFromValue(status);
      if (parsed != TimelineTaskStatus.unknown) return parsed;
    }
    // Older snapshots may expose only a current turn object.  It is still a
    // valid lifecycle source and, importantly, understands `inProgress`.
    final currentTurn =
        _asMap(thread['turn']) ??
        _asMap(thread['currentTurn']) ??
        _asMap(thread['current_turn']);
    if (currentTurn != null) return _timelineStatusFromTurn(currentTurn);
    return TimelineTaskStatus.unknown;
  }

  bool _shouldIgnoreTerminalLifecycle({
    required String? threadId,
    required String? turnId,
    required TimelineTaskStatus status,
  }) {
    if (!status.isTerminal) return false;

    final selectedId = selectedSessionId.value?.trim();
    final currentId = currentSessionId.value?.trim();
    final incomingThreadId = threadId?.trim();
    if (_pendingSessionStart &&
        (selectedId == null || selectedId.isEmpty) &&
        (currentId == null || currentId.isEmpty)) {
      // Until thread.create returns there is no known target thread. A
      // terminal event at this point can only belong to a previous task.
      return true;
    }
    if (incomingThreadId != null && incomingThreadId.isNotEmpty) {
      final hasKnownThread =
          (selectedId != null && selectedId.isNotEmpty) ||
          (currentId != null && currentId.isNotEmpty);
      if (hasKnownThread) {
        final isSelected = selectedId != null && incomingThreadId == selectedId;
        final isCurrent = currentId != null && incomingThreadId == currentId;
        if (!isSelected && !isCurrent) return true;
      }
    }

    final activeTurnId = _currentTurnId?.trim();
    final lastTerminalTurnId = _lastTerminalTurnId?.trim();
    final incomingTurnId = turnId?.trim();
    if (incomingTurnId != null &&
        incomingTurnId.isNotEmpty &&
        lastTerminalTurnId != null &&
        incomingTurnId == lastTerminalTurnId &&
        activeTurnId != incomingTurnId) {
      // A new active state may be observed before its turn.started event. In
      // that short window the previous terminal turn remains the only known
      // id, so reject its late terminal notification explicitly.
      return true;
    }
    if (incomingTurnId != null &&
        incomingTurnId.isNotEmpty &&
        activeTurnId != null &&
        activeTurnId.isNotEmpty &&
        incomingTurnId != activeTurnId) {
      // A terminal event from a previous turn must never end the latest turn
      // in the selected thread.
      return true;
    }
    final lifecycleIsActive =
        incomingThreadId != null &&
        incomingThreadId.isNotEmpty &&
        _sessionLifecycles[incomingThreadId]?.visibleRunning == true;
    if ((timelineStatus.value.isActive || lifecycleIsActive) &&
        (incomingTurnId == null || incomingTurnId.isEmpty)) {
      // App Server status patches do not always carry a turn id. While a turn
      // is visibly active, an unscoped terminal patch is ambiguous and is
      // safely deferred to the next authoritative thread.read snapshot.
      return true;
    }

    if (timelineStatus.value.isTerminal) {
      // Ignore duplicate terminal notifications after the selected task has
      // already reached a terminal state. A new turn will first transition
      // the timeline back to an active state and replace [_currentTurnId].
      return true;
    }
    return false;
  }

  void _handleThreadUpdated(
    Map<String, dynamic> data, {
    String? threadId,
    String? turnId,
  }) {
    final thread = _asMap(data['thread']) ?? data;
    final id =
        threadId ??
        _readString(thread['id']) ??
        _readString(thread['threadId']) ??
        _readString(thread['thread_id']);
    if (id == null || id.trim().isEmpty) return;
    final status = _timelineStatusFromThread(thread);
    if (_shouldIgnoreTerminalLifecycle(
      threadId: id,
      turnId: turnId,
      status: status,
    )) {
      return;
    }
    if (status.isTerminal) {
      // Preserve observedRunning for completion notifications, but stop
      // projecting the stale local lifecycle back onto the next thread.list.
      _sessionLifecycle(id).visibleRunning = false;
      final terminalTurnId = turnId?.trim();
      if (terminalTurnId != null && terminalTurnId.isNotEmpty) {
        _currentTurnId = terminalTurnId;
        _lastTerminalTurnId = terminalTurnId;
      }
    }

    // `thread/status/changed` is a patch, not a complete Thread object. Merge
    // it into the existing sidebar row so a status heartbeat cannot erase the
    // title, workspace, prompt, or timestamps returned by thread.list.
    final parsed = _sessionFromThread(data);
    SessionRecord? existing;
    for (final session in sessions) {
      if (session.id.trim() == id.trim()) {
        existing = session;
        break;
      }
    }
    if (parsed != null || existing != null) {
      final base = existing ?? parsed!;
      final merged = existing == null
          ? parsed!
          : base.copyWith(
              workspace: parsed?.workspace.trim().isNotEmpty == true
                  ? parsed!.workspace
                  : base.workspace,
              prompt: parsed?.prompt.trim().isNotEmpty == true
                  ? parsed!.prompt
                  : base.prompt,
              status: parsed?.status.trim().isNotEmpty == true
                  ? parsed!.status
                  : base.status,
              createdAt: parsed?.createdAt.trim().isNotEmpty == true
                  ? parsed!.createdAt
                  : base.createdAt,
              updatedAt: parsed?.updatedAt.trim().isNotEmpty == true
                  ? parsed!.updatedAt
                  : base.updatedAt,
              title: parsed?.title.trim().isNotEmpty == true
                  ? parsed!.title
                  : base.title,
              isPinned: parsed?.isPinned == true || base.isPinned,
              isArchived: parsed?.isArchived == true || base.isArchived,
            );
      _upsertSession(merged);
    }

    if (status == TimelineTaskStatus.unknown) return;
    final selectedId = selectedSessionId.value?.trim();
    if (selectedId != id.trim()) return;
    DateTime? statusStartedAt;
    if (status.isActive) {
      currentSessionId.value = id;
      if (timelineStatus.value.isTerminal ||
          timelineTurnStartedAt.value == null) {
        _currentTurnStartedAt = DateTime.now();
      }
      statusStartedAt = _currentTurnStartedAt;
      final activeTurnId = turnId?.trim();
      if (activeTurnId != null &&
          activeTurnId.isNotEmpty &&
          activeTurnId != _lastTerminalTurnId &&
          // Do not replace a newer locally observed turn with a stale id
          // carried by a status patch from an older server implementation.
          (!timelineStatus.value.isActive ||
              _currentTurnId == null ||
              _currentTurnId == activeTurnId)) {
        _currentTurnId = activeTurnId;
        _lastTerminalTurnId = null;
      } else if (timelineStatus.value.isTerminal) {
        // The status patch can arrive before turn.started and may not carry a
        // turn id. Clear the previous tombstone; the next terminal event will
        // be checked against [_lastTerminalTurnId] until a new id is known.
        _currentTurnId = null;
      }
      _markSessionRunningForNotification(id);
    }
    _setTimelineStatus(
      status,
      startedAt: statusStartedAt,
      activeFlags: _threadActiveFlags(thread),
    );
    if (status.isActive && (events.isEmpty || events.last.kind != 'running')) {
      _appendSessionEvent(SessionEvent(kind: 'running', text: status.label));
    }
  }

  void _handleThreadCreated(Object? value) {
    final record =
        _sessionFromThread(value) ??
        SessionRecord(
          id:
              _readString(_asMap(_asMap(value)?['thread'])?['id']) ??
              _readString(_asMap(_asMap(value)?['thread'])?['thread_id']) ??
              _readString(_asMap(value)?['thread_id']) ??
              '',
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
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _currentTurnStartedAt = null;
    _storedSessionId = record.id;
    _sessionRestoreAttempted = true;
    unawaited(_storeSelectedSession(record.id));
    _setTimelineStatus(TimelineTaskStatus.processing);
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

  void _handleThreadReadResult(Object? value, {int? readGeneration}) {
    // The response handler is intentionally generation-aware.  Relay and
    // Codex can finish an older read after a newer forced refresh; accepting
    // that snapshot would resurrect an old interrupted turn and overwrite
    // live output from the current turn.
    if (readGeneration != null && readGeneration != _timelineReadGeneration) {
      return;
    }
    final map = _asMap(value);
    final thread = _asMap(map?['thread']) ?? map;
    final requestedSessionId = _requestedEventsSessionId;
    if (requestedSessionId == null || requestedSessionId.isEmpty) return;
    if (thread == null) {
      _failTimelineLoad(
        '任务对话加载失败：目标主机未返回有效内容，请重试。',
        sessionId: requestedSessionId,
      );
      return;
    }
    final sessionId = _readString(thread['id']) ?? requestedSessionId;
    if (sessionId != requestedSessionId) return;
    final turns = _asList(thread['turns']);
    final latestTurn = _latestTurnFromSnapshot(turns);
    final latestTurnStatus = latestTurn == null
        ? TimelineTaskStatus.unknown
        : _timelineStatusFromTurn(latestTurn);
    final latestTurnId = latestTurn == null
        ? null
        : _turnIdFromTurn(latestTurn);
    final threadSnapshotStatus = _timelineStatusFromThread(thread);
    final threadIsWaiting =
        threadSnapshotStatus == TimelineTaskStatus.waitingApproval ||
        threadSnapshotStatus == TimelineTaskStatus.waitingUserInput;
    // The thread-level active state is the freshest lifecycle signal. A
    // paginated read can briefly contain the previous turn as its last item
    // while the new turn is already running, so never let that stale terminal
    // turn override an active thread snapshot.
    final threadIsActive = threadSnapshotStatus.isActive;
    // A thread.read response can contain the previous turn while the new
    // turn is already running.  In that case the previous turn's terminal
    // status (especially `interrupted`) must not replace the local active
    // lifecycle.  Terminal snapshots are only trusted when they describe
    // the turn that is currently tracked by this controller.
    final localStatusIsActive =
        timelineStatus.value.isActive ||
        _sessionLifecycles[sessionId]?.visibleRunning == true;
    final localActiveStatus = timelineStatus.value.isActive
        ? timelineStatus.value
        : TimelineTaskStatus.processing;
    final latestTurnMatchesCurrent =
        latestTurnId != null &&
        _currentTurnId != null &&
        latestTurnId == _currentTurnId;
    final latestTerminalIsStale =
        localStatusIsActive &&
        latestTurnStatus.isTerminal &&
        !latestTurnMatchesCurrent;
    final localActiveShouldWin =
        localStatusIsActive &&
        !latestTurnMatchesCurrent &&
        !latestTurnStatus.isActive &&
        (latestTurnStatus == TimelineTaskStatus.unknown ||
            latestTurnStatus.isTerminal) &&
        (threadSnapshotStatus == TimelineTaskStatus.unknown ||
            threadSnapshotStatus.isTerminal);
    final snapshotStatus = threadIsWaiting
        ? threadSnapshotStatus
        : threadIsActive
        ? threadSnapshotStatus
        : latestTurnStatus.isActive
        ? latestTurnStatus
        : latestTerminalIsStale || localActiveShouldWin
        ? localActiveStatus
        : latestTurnStatus != TimelineTaskStatus.unknown
        ? latestTurnStatus
        : threadSnapshotStatus;
    // An active thread can legitimately have a terminal previous turn as
    // the last item in a paginated snapshot.  Never promote that historical
    // id to [_currentTurnId]; doing so makes the next delayed
    // `turn.interrupted`/`turn.completed` notification terminate the live
    // turn.  A turn id is safe to adopt only when its own status is active or
    // indeterminate.
    final staleTerminalTurnInActiveSnapshot =
        snapshotStatus.isActive && latestTurnStatus.isTerminal;
    final latestStartedAt = latestTurn == null
        ? null
        : _turnTimestamp(latestTurn, 'startedAt');
    final resolvedStartedAt = snapshotStatus.isActive
        ? latestStartedAt ?? timelineTurnStartedAt.value ?? DateTime.now()
        : latestStartedAt;
    if (snapshotStatus != TimelineTaskStatus.unknown) {
      _setTimelineStatus(
        snapshotStatus,
        startedAt: resolvedStartedAt,
        activeFlags: _threadActiveFlags(thread),
      );
      if (snapshotStatus.isActive) {
        currentSessionId.value = sessionId;
        _currentTurnStartedAt = resolvedStartedAt;
        // `thread.read` is authoritative only for the turn it describes.
        // In particular, do not replace a locally tracked active turn with a
        // terminal id from an older paginated snapshot.
        if (latestTurnId != null && !staleTerminalTurnInActiveSnapshot) {
          _currentTurnId = latestTurnId;
          if (!latestTurnStatus.isTerminal) _lastTerminalTurnId = null;
        } else if (staleTerminalTurnInActiveSnapshot &&
            (latestTurnMatchesCurrent || _currentTurnId == null)) {
          // The only turn visible in the snapshot is terminal.  Keep it as a
          // tombstone and clear the active id, unless a different locally
          // observed turn is already running.
          _lastTerminalTurnId = latestTurnId ?? _lastTerminalTurnId;
          _currentTurnId = null;
        } else if (staleTerminalTurnInActiveSnapshot) {
          // A different locally observed turn is newer than the historical
          // terminal item; leave its id untouched.
        } else if (_lastTerminalTurnId != null) {
          // Keep the previous terminal id as a tombstone when this server
          // omits the active turn id from its snapshot.
          _currentTurnId = null;
        }
        _markSessionRunningForNotification(sessionId);
      } else if (latestTurnId != null) {
        // Keep the last observed turn id while the selected task is terminal.
        // It lets us reject a late `turn.completed`/`turn.interrupted` event
        // that belongs to an older turn even when the event has no active
        // session to compare against.
        _currentTurnId = latestTurnId;
        _lastTerminalTurnId = latestTurnId;
      }
    } else if (timelineStatus.value == TimelineTaskStatus.loading) {
      // A valid snapshot without lifecycle fields is still not proof of
      // completion. Keep the synchronizing state until a terminal event or a
      // later catalog refresh provides an explicit status.
      _setTimelineStatus(
        TimelineTaskStatus.unknown,
        startedAt: latestStartedAt,
      );
    }
    final loaded = <SessionEvent>[];
    final prompt = _requestedEventsPrompt;
    var promptWasAdded = false;
    if (prompt != null && prompt.trim().isNotEmpty) {
      loaded.add(SessionEvent(kind: 'user', text: prompt.trim()));
      promptWasAdded = true;
    }
    for (final turn in turns) {
      final turnMap = _asMap(turn);
      if (turnMap == null) continue;
      final turnStatus = _timelineStatusFromTurn(turnMap);
      final turnStartedAt = _turnTimestamp(turnMap, 'startedAt');
      final turnCompletedAt = _turnTimestamp(turnMap, 'completedAt');
      final turnDurationMs = _turnDurationMs(turnMap);
      final snapshotTurnId = _turnIdFromTurn(turnMap);
      final turnEvents = <SessionEvent>[];
      for (final item in _asList(turnMap['items'])) {
        final event = _eventFromCodexItem(item, turnId: snapshotTurnId);
        if (event == null) continue;
        if (promptWasAdded &&
            event.kind == 'user' &&
            (_matchesRequestedPrompt(event.text, prompt!) ||
                (event.text.trim().isEmpty && event.attachments.isNotEmpty))) {
          final promptEvent = loaded.first;
          loaded[0] = SessionEvent(
            kind: promptEvent.kind,
            text: promptEvent.text,
            time: event.time ?? turnStartedAt ?? promptEvent.time,
            usage: event.usage ?? promptEvent.usage,
            attachments: _mergeEventAttachments(
              promptEvent.attachments,
              event.attachments,
            ),
          );
          promptWasAdded = false;
          continue;
        }
        turnEvents.add(event);
      }
      final timedTurnEvents = _applyTurnTiming(
        turnEvents,
        startedAt: turnStartedAt,
        completedAt: turnCompletedAt,
        durationMs: turnDurationMs,
      );
      loaded.addAll(timedTurnEvents);

      // A newly-created or user-only turn may have no answer item to carry
      // its timing metadata. Keep an invisible terminal marker so the
      // completed answer header can still show the measured duration.
      final hasAnswerEvent = timedTurnEvents.any(
        (event) => event.kind != 'user',
      );
      final hasExplicitTerminal =
          turnStatus.isTerminal ||
          (turnStatus == TimelineTaskStatus.unknown &&
              (turnDurationMs != null || turnCompletedAt != null));
      if (!hasAnswerEvent &&
          hasExplicitTerminal &&
          (turnDurationMs != null ||
              turnStartedAt != null ||
              turnCompletedAt != null)) {
        final resolvedDuration =
            turnDurationMs ?? _durationBetween(turnStartedAt, turnCompletedAt);
        loaded.add(
          SessionEvent(
            kind: 'done',
            text: '',
            time: turnCompletedAt ?? turnStartedAt,
            durationMs: resolvedDuration,
          ),
        );
      }
    }
    if (snapshotStatus.isActive &&
        !loaded.any((event) => event.kind == 'running')) {
      loaded.add(
        SessionEvent(
          kind: 'running',
          text: snapshotStatus == TimelineTaskStatus.waitingApproval
              ? '等待主机审批...'
              : snapshotStatus == TimelineTaskStatus.waitingUserInput
              ? '等待你的输入...'
              : 'Codex 正在执行...',
          time: resolvedStartedAt,
        ),
      );
    }
    // An empty thread is a valid response (for example, a newly-created
    // task that has not produced output yet). It must still end the loading
    // state so the user gets an actionable empty state instead of a spinner
    // that never resolves.
    _finishTimelineLoad(sessionId: requestedSessionId);
    if (loaded.isEmpty) return;
    final merged = _mergeLiveEvents(loaded);
    if (!_hasSameTimelineEvents(events, merged)) {
      events.assignAll(merged);
      _bumpTimelineRevision();
    }
  }

  /// App Server versions have returned turns in both chronological and
  /// reverse-chronological order.  Selecting the last array item therefore
  /// occasionally picked an older interrupted turn while a newer turn was
  /// still in progress.  Prefer an active turn whenever one exists, then use
  /// the newest lifecycle timestamp for terminal/unknown turns.
  Map<String, dynamic>? _latestTurnFromSnapshot(List<Object?> turns) {
    Map<String, dynamic>? latest;
    TimelineTaskStatus latestStatus = TimelineTaskStatus.unknown;
    DateTime? latestTime;

    DateTime? recency(Map<String, dynamic> turn) {
      for (final field in const [
        'completedAt',
        'startedAt',
        'updatedAt',
        'createdAt',
      ]) {
        final timestamp = _turnTimestamp(turn, field);
        if (timestamp != null) return timestamp;
      }
      return null;
    }

    for (final rawTurn in turns) {
      final candidate = _asMap(rawTurn);
      if (candidate == null) continue;
      final status = _timelineStatusFromTurn(candidate);
      final candidateTime = recency(candidate);
      final candidateIsActive = status.isActive;
      final latestIsActive = latestStatus.isActive;
      final shouldReplace =
          latest == null ||
          (candidateIsActive && !latestIsActive) ||
          (candidateIsActive == latestIsActive &&
              (latestTime == null ||
                  (candidateTime != null &&
                      candidateTime.isAfter(latestTime))));
      if (shouldReplace) {
        latest = candidate;
        latestStatus = status;
        latestTime = candidateTime;
      }
    }
    return latest;
  }

  SessionEvent? _eventFromCodexItem(Object? value, {String? turnId}) {
    final item = _asMap(value);
    if (item == null) return null;
    final type = (_readString(item['type']) ?? '')
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll('.', '_');
    var text = _extractText(item);
    final attachments = _extractAttachments(item);
    final usage = _extractTokenUsage(item);
    final isFileChange =
        type == 'filechange' ||
        type == 'file_change' ||
        type == 'filechanged' ||
        type == 'file_changed';
    if (isFileChange && text.isEmpty) {
      text = _extractFileChangePaths(item).join('\n');
    }
    if (text.isEmpty && type.isEmpty && attachments.isEmpty && usage == null) {
      return null;
    }
    // Protocol-only items do not carry user-facing information.  Returning
    // null here prevents labels such as `filechange` or `item.completed`
    // from leaking into the conversation transcript.
    final protocolOnlyType =
        type == 'filechange' ||
        type == 'file_change' ||
        type == 'item_started' ||
        type == 'item_completed';
    if (text.isEmpty &&
        attachments.isEmpty &&
        usage == null &&
        protocolOnlyType) {
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
        : isFileChange
        ? 'file_change'
        : usageEvent
        ? 'token_usage'
        : 'event';
    return SessionEvent(
      kind: kind,
      // Attachment-only items do not have user-visible copy. Leaving their
      // text empty lets the timeline render the thumbnail without leaking
      // protocol type names such as "userMessage" or "image".
      text: text,
      time: _dateTime(
        item['time'] ??
            item['timestamp'] ??
            item['createdAt'] ??
            item['created_at'],
      ),
      usage: usage,
      attachments: attachments,
      itemId: _eventItemId(item),
      turnId: turnId,
    );
  }

  String? _eventItemId(Map<String, dynamic> value) {
    final item = _asMap(value['item']);
    return _readString(value['itemId']) ??
        _readString(value['item_id']) ??
        _readString(value['id']) ??
        _readString(item?['itemId']) ??
        _readString(item?['item_id']) ??
        _readString(item?['id']);
  }

  /// Accept both the canonical Relay names and notification aliases emitted
  /// by newer App Server builds. Keeping this normalization at the client
  /// boundary also lets an older plugin forward a raw method unchanged.
  String _normalizeCodexEventType(String rawType) {
    final normalized = rawType.trim().toLowerCase();
    return switch (normalized) {
      'thread/started' || 'thread.started' => 'thread.created',
      // Relay forwards the canonical normalized event type. Keep accepting
      // it here as well as the raw App Server method spelling below; without
      // this branch a valid streamed delta falls through to the generic
      // event handler and never updates the live answer buffer/status.
      'thread.created' => 'thread.created',
      'thread/status/changed' ||
      'thread/statuschanged' ||
      'thread.status.changed' => 'thread.updated',
      'thread.updated' => 'thread.updated',
      'turn/started' || 'turn.started' => 'turn.started',
      'turn/completed' || 'turn.completed' => 'turn.completed',
      'turn/failed' ||
      'turn.failed' ||
      'turn/error' ||
      'turn.error' => 'turn.failed',
      'turn/aborted' ||
      'turn/interrupted' ||
      'turn.interrupted' => 'turn.interrupted',
      'turn.heartbeat' => 'turn.heartbeat',
      'turn/status/changed' || 'turn/statuschanged' => 'thread.updated',
      'processing/heartbeat' || 'processing.heartbeat' => 'turn.heartbeat',
      'message.assistant.delta' => 'message.assistant.delta',
      'reasoning.delta' => 'reasoning.delta',
      'tool.output' => 'tool.output',
      'diff.updated' => 'diff.updated',
      'item/agentmessage/delta' ||
      'item.agentmessage.delta' ||
      'item/agentmessage/textdelta' ||
      'item.agentmessage.textdelta' ||
      'item/agentmessage/text_delta' ||
      'item/agentmessage/text/delta' ||
      'item/agent_message/delta' ||
      'text:delta' ||
      'text/delta' => 'message.assistant.delta',
      'item/reasoning/summarytextdelta' ||
      'item.reasoning.summarytextdelta' ||
      'item/reasoning/summary_text_delta' ||
      'item/reasoning/textdelta' ||
      'item/reasoning/text_delta' ||
      'item/reasoning/summarytext/delta' => 'reasoning.delta',
      'item/commandexecution/outputdelta' ||
      'item.commandexecution.outputdelta' ||
      'item/commandexecution/output_delta' ||
      'item/commandexecution/output/delta' ||
      'item/command_execution/output_delta' => 'tool.output',
      'item/filechange/outputdelta' ||
      'item.filechange.outputdelta' ||
      'item/filechange/output_delta' ||
      'item/filechange/output/delta' ||
      'item/file_change/output_delta' => 'diff.updated',
      'item/started' || 'item.started' => 'item.started',
      'item/updated' || 'item.updated' => 'item.updated',
      'item/completed' || 'item.completed' => 'item.completed',
      _ => rawType,
    };
  }

  List<String> _extractFileChangePaths(Map<String, dynamic> item) {
    final paths = <String>{};

    void addPath(Object? value) {
      if (value is String) {
        for (final raw in value.split(RegExp(r'[\n,;]'))) {
          var path = raw.trim();
          path = path.replaceFirst(RegExp(r'''^["']'''), '');
          path = path.replaceFirst(RegExp(r'''["']$'''), '');
          if (path.isEmpty || path == '.' || path == '/') continue;
          final normalizedPath = path.toLowerCase();
          if (normalizedPath == 'filechange' ||
              normalizedPath == 'file_change' ||
              normalizedPath == 'updated' ||
              normalizedPath == 'modified' ||
              normalizedPath == 'changed') {
            continue;
          }
          paths.add(path);
        }
      } else if (value is List) {
        for (final entry in value) {
          addPath(entry);
        }
      } else if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        for (final key in const [
          'path',
          'file',
          'filename',
          'filePath',
          'file_path',
          'name',
        ]) {
          addPath(map[key]);
        }
        for (final key in const [
          'files',
          'changes',
          'diffs',
          'content',
          'data',
          'details',
        ]) {
          addPath(map[key]);
        }
      }
    }

    for (final key in const [
      'path',
      'file',
      'filename',
      'filePath',
      'file_path',
      'files',
      'changes',
      'diffs',
      'content',
      'data',
      'details',
    ]) {
      addPath(item[key]);
    }
    return paths.toList(growable: false);
  }

  void _handleCodexEvent(Map<String, dynamic> message) {
    // `codex.event` is an intentionally opaque product payload.  The relay
    // normally places the normalized event in `event`, but older connector
    // builds used `payload`/`notification` and some App Server versions used
    // `params` instead of `data`.  Accept all of those shapes at this single
    // boundary so a valid delta cannot disappear silently during an upgrade.
    // A connector normally puts the notification under `event`, but older
    // builds used `notification`/`payload` and a few adapters put the
    // normalized notification directly under `data` (or at the envelope
    // root). Accept all of those shapes here. Keeping this compatibility at
    // the transport boundary is important for streaming: dropping one outer
    // wrapper makes every subsequent delta look like a silent network stall.
    final event =
        _asMap(message['event']) ??
        _asMap(message['notification']) ??
        _asMap(message['payload']) ??
        _asMap(message['data']) ??
        ((message.containsKey('method') || message.containsKey('type'))
            ? message
            : null);
    if (event == null) return;
    final rawType =
        _readString(event['type']) ??
        _readString(event['method']) ??
        _readString(message['eventType']) ??
        _readString(message['method']) ??
        '';
    final type = _normalizeCodexEventType(rawType);
    final data = _codexEventData(event);
    final nestedTurn = _asMap(data['turn']);
    final turnData = nestedTurn ?? data;
    final eventTurnId =
        _readString(message['turnId']) ??
        _readString(message['turn_id']) ??
        _readString(event['turnId']) ??
        _readString(event['turn_id']) ??
        _readString(data['turnId']) ??
        _readString(data['turn_id']) ??
        _turnIdFromTurn(nestedTurn ?? const <String, dynamic>{}) ??
        _readString(_asMap(data['item'])?['turnId']) ??
        _readString(_asMap(data['item'])?['turn_id']);
    final eventUsage = _extractTokenUsage(data);
    final explicitThreadId =
        _readString(message['threadId']) ??
        _readString(message['thread_id']) ??
        _readString(event['threadId']) ??
        _readString(event['thread_id']) ??
        _readString(data['threadId']) ??
        _readString(data['thread_id']) ??
        _readString(_asMap(data['thread'])?['id']) ??
        _readString(_asMap(data['thread'])?['threadId']) ??
        _readString(_asMap(data['thread'])?['thread_id']) ??
        _readString(_asMap(data['item'])?['threadId']) ??
        _readString(_asMap(data['item'])?['thread_id']);
    final threadId =
        explicitThreadId ??
        currentSessionId.value ??
        // Terminal handling clears currentSessionId, but the selected task
        // remains the destination for late/streaming events that omit the
        // envelope context.  Falling back to the selected id keeps output
        // attached to the visible task without accepting events from a
        // different thread.
        selectedSessionId.value;
    final selectedId = selectedSessionId.value?.trim();
    // A blank transcript is an intentional new-conversation state. Ignore
    // unscoped/background events until the pending new thread is selected,
    // otherwise an old task could repopulate the freshly cleared view.
    if ((selectedId == null || selectedId.isEmpty) && !_pendingSessionStart) {
      return;
    }
    if (threadId != null && threadId.isNotEmpty) {
      if (selectedId != null &&
          selectedId.isNotEmpty &&
          threadId != selectedId) {
        return;
      }
    }
    if (type == 'turn.completed' ||
        type == 'turn.failed' ||
        type == 'turn.interrupted') {
      if (explicitThreadId == null && eventTurnId == null) {
        // Terminal notifications without either thread or turn context are
        // not attributable to the selected task.  Accepting one would make
        // an unrelated/late event paint the conversation as interrupted.
        return;
      }
      final terminalStatus = _timelineStatusFromValue(
        type.substring('turn.'.length),
      );
      if (_shouldIgnoreTerminalLifecycle(
        threadId: threadId,
        turnId: eventTurnId,
        status: terminalStatus,
      )) {
        return;
      }
      if (eventTurnId != null && eventTurnId.isNotEmpty) {
        _currentTurnId = eventTurnId;
      }
    }
    if (type == 'thread.updated' &&
        _shouldIgnoreTerminalLifecycle(
          threadId: threadId,
          turnId: eventTurnId,
          status: _timelineStatusFromThread(_asMap(data['thread']) ?? data),
        )) {
      return;
    }
    if (threadId != null &&
        threadId.isNotEmpty &&
        currentSessionId.value == null) {
      currentSessionId.value = threadId;
    }
    // A live item/delta notification is positive evidence that the turn is
    // still executing, even if `turn.started` was lost or a stale read marked
    // the timeline terminal during reconnect. Promote that stale snapshot to
    // processing so the phone immediately renders the live thinking state.
    final isLiveDelta =
        type == 'message.assistant.delta' ||
        type == 'reasoning.delta' ||
        type == 'tool.output' ||
        type == 'diff.updated' ||
        type == 'turn.heartbeat' ||
        // Codex emits item.started while a tool is opening/reading a file.
        // This is the first visible signal in many turns, so it must promote
        // a stale terminal snapshot back to the running state as well.
        type == 'item.started' ||
        type == 'item.completed';
    if (threadId != null && threadId.isNotEmpty && isLiveDelta) {
      // A non-empty live delta is stronger evidence than a stale terminal
      // snapshot. In practice `turn.started` can be lost during reconnect or
      // an older App Server can emit an early `turn.interrupted` patch while
      // the same turn continues producing output. Rejecting this delta based
      // solely on [_lastTerminalTurnId] permanently freezes the answer. The
      // next terminal event is still guarded by its thread/turn identity, so
      // accepting the live evidence here does not weaken normal completion
      // handling.
      final liveText = _extractText(data);
      final canReviveTerminal =
          liveText.isNotEmpty ||
          type == 'message.assistant.delta' ||
          type == 'reasoning.delta' ||
          type == 'tool.output' ||
          type == 'diff.updated';
      if (canReviveTerminal) {
        if (eventTurnId != null && eventTurnId.isNotEmpty) {
          _currentTurnId = eventTurnId;
          _lastTerminalTurnId = null;
        }
      } else if (eventTurnId == null && timelineStatus.value.isTerminal) {
        // A lifecycle-only event without a turn id remains ambiguous after a
        // terminal state. Wait for a real delta or an identified turn start.
        return;
      }
      final activityStartedAt =
          _currentTurnStartedAt ??
          _turnTimestamp(turnData, 'startedAt') ??
          _dateTime(message['timestamp']) ??
          DateTime.now();
      _currentTurnStartedAt = activityStartedAt;
      if (eventTurnId != null && eventTurnId.isNotEmpty) {
        _currentTurnId = eventTurnId;
        _lastTerminalTurnId = null;
      }
      _setTimelineStatus(
        TimelineTaskStatus.processing,
        startedAt: activityStartedAt,
      );
      _markSessionRunningForNotification(threadId);
    }
    switch (type) {
      case 'thread.created':
        final record = _sessionFromThread(data);
        if (record != null) {
          _upsertSession(record);
          _deriveWorkspaces(sessions);
        }
      case 'thread.updated':
        _handleThreadUpdated(data, threadId: threadId, turnId: eventTurnId);
      case 'turn.started':
        // A new start replaces the tombstoned id from the previous turn. If
        // this older App Server variant omits the id, clear the tombstone so
        // subsequent unscoped events are not mistaken for stale events.
        _currentTurnId =
            eventTurnId ??
            (timelineStatus.value.isTerminal ? null : _currentTurnId);
        if (eventTurnId != null) _lastTerminalTurnId = null;
        final startedAt =
            _turnTimestamp(turnData, 'startedAt') ??
            _dateTime(message['timestamp']) ??
            DateTime.now();
        _currentTurnStartedAt = startedAt;
        if (threadId != null && threadId.isNotEmpty) {
          currentSessionId.value = threadId;
          _setTimelineStatus(
            TimelineTaskStatus.processing,
            startedAt: startedAt,
          );
          _markSessionRunningForNotification(threadId);
        }
        _appendSessionEvent(
          SessionEvent(kind: 'running', text: 'Codex 正在执行...', time: startedAt),
        );
        _sendRequestedInterrupt();
      case 'message.assistant.delta':
        _appendSessionEvent(
          SessionEvent(
            kind: 'assistant',
            text: _extractText(data),
            usage: eventUsage,
            attachments: _extractAttachments(data),
            itemId: _eventItemId(data) ?? _eventItemId(event),
            turnId: eventTurnId,
            isDelta: true,
          ),
        );
      case 'reasoning.delta':
        _appendSessionEvent(
          SessionEvent(
            kind: 'reasoning',
            text: _extractText(data),
            usage: eventUsage,
            attachments: _extractAttachments(data),
            itemId: _eventItemId(data) ?? _eventItemId(event),
            turnId: eventTurnId,
            isDelta: true,
          ),
        );
      case 'tool.output':
        _appendSessionEvent(
          SessionEvent(
            kind: 'tool_call',
            text: _extractText(data),
            usage: eventUsage,
            attachments: _extractAttachments(data),
            itemId: _eventItemId(data) ?? _eventItemId(event),
            turnId: eventTurnId,
            isDelta: true,
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
          SessionEvent(
            kind: 'git_change',
            text: _extractText(data),
            itemId: _eventItemId(data) ?? _eventItemId(event),
            turnId: eventTurnId,
            isDelta: true,
          ),
        );
      case 'item.started':
      case 'item.updated':
      case 'item.completed':
        final snapshot = _eventFromCodexItem(
          _asMap(data['item']) ?? data,
          turnId: eventTurnId,
        );
        if (snapshot != null) _appendSessionEvent(snapshot);
      case 'turn.heartbeat':
        // Heartbeats are lifecycle evidence only. The active status was
        // promoted above; adding a transcript row for every heartbeat would
        // make the answer grow indefinitely while no text is produced.
        break;
      case 'turn.completed':
        if (_shouldIgnoreTerminalLifecycle(
          threadId: threadId,
          turnId: eventTurnId,
          status: TimelineTaskStatus.completed,
        )) {
          return;
        }
        final text = _extractText(data);
        final completedTurnStartedAt =
            _turnTimestamp(turnData, 'startedAt') ?? _currentTurnStartedAt;
        final completedTurnAt =
            _turnTimestamp(turnData, 'completedAt') ??
            _dateTime(message['timestamp']) ??
            DateTime.now();
        final completedDurationMs =
            _turnDurationMs(turnData) ??
            _durationBetween(completedTurnStartedAt, completedTurnAt);
        _appendSessionEvent(
          SessionEvent(
            kind: 'done',
            text: text.isEmpty ? 'Codex 任务已完成' : text,
            time: completedTurnAt,
            durationMs: completedDurationMs,
            usage: eventUsage,
          ),
        );
        _finishCurrentSession(
          status: TaskNotificationStatus.completed,
          sessionId: threadId,
        );
      case 'turn.failed':
        if (_shouldIgnoreTerminalLifecycle(
          threadId: threadId,
          turnId: eventTurnId,
          status: TimelineTaskStatus.failed,
        )) {
          return;
        }
        final extracted = _extractText(data);
        final text = extracted.isEmpty ? 'Codex 任务失败' : extracted;
        final failedTurnStartedAt =
            _turnTimestamp(turnData, 'startedAt') ?? _currentTurnStartedAt;
        final failedTurnAt =
            _turnTimestamp(turnData, 'completedAt') ??
            _dateTime(message['timestamp']) ??
            DateTime.now();
        final failedDurationMs =
            _turnDurationMs(turnData) ??
            _durationBetween(failedTurnStartedAt, failedTurnAt);
        _appendSessionEvent(
          SessionEvent(
            kind: 'error',
            text: text,
            time: failedTurnAt,
            durationMs: failedDurationMs,
          ),
        );
        _finishCurrentSession(
          status: TaskNotificationStatus.failed,
          sessionId: threadId,
          message: text,
        );
      case 'turn.interrupted':
        if (_shouldIgnoreTerminalLifecycle(
          threadId: threadId,
          turnId: eventTurnId,
          status: TimelineTaskStatus.interrupted,
        )) {
          return;
        }
        final interruptedTurnStartedAt =
            _turnTimestamp(turnData, 'startedAt') ?? _currentTurnStartedAt;
        final interruptedTurnAt =
            _turnTimestamp(turnData, 'completedAt') ??
            _dateTime(message['timestamp']) ??
            DateTime.now();
        final interruptedDurationMs =
            _turnDurationMs(turnData) ??
            _durationBetween(interruptedTurnStartedAt, interruptedTurnAt);
        _appendSessionEvent(
          SessionEvent(
            kind: 'interrupted',
            text: '已被用户中断。',
            time: interruptedTurnAt,
            durationMs: interruptedDurationMs,
          ),
        );
        _finishCurrentSession(
          status: TaskNotificationStatus.interrupted,
          sessionId: threadId,
        );
      case 'approval.requested':
        _setTimelineStatus(
          TimelineTaskStatus.waitingApproval,
          activeFlags: const ['waitingOnApproval'],
        );
        _appendSessionEvent(
          const SessionEvent(kind: 'running', text: '等待主机审批...'),
        );
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
    _lastTerminalTurnId = _currentTurnId;
    unawaited(
      _notifySessionFinishedOnce(
        status: status,
        sessionId: id,
        errorMessage: message,
      ),
    );
    currentSessionId.value = null;
    // Keep the last turn id as a tombstone until another task/turn is
    // selected. This prevents a delayed terminal notification from the just
    // finished turn from changing its final state a second time.
    _interruptRequested = false;
    _setTimelineStatus(switch (status) {
      TaskNotificationStatus.failed => TimelineTaskStatus.failed,
      TaskNotificationStatus.interrupted => TimelineTaskStatus.interrupted,
      _ => TimelineTaskStatus.completed,
    });
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

  bool _sendCommand(
    String type,
    Map<String, dynamic> command, {
    String? threadId,
    String? turnId,
    bool force = false,
    int? refreshToken,
  }) {
    if (!connected.value ||
        targetDeviceId.value.isEmpty ||
        spaceId.value.isEmpty) {
      return false;
    }
    _expirePendingCommands();
    if (_coalescesPendingCommand(type) &&
        !force &&
        _pendingCommands.values.any(
          (pending) => pending.matches(type, threadId: threadId),
        )) {
      return false;
    }
    if (force && _coalescesPendingCommand(type)) {
      // A user refresh must not be swallowed by the in-flight periodic poll.
      // Its response remains valid on the wire, but removing the old entry
      // makes the matching result a no-op when it eventually arrives.
      _pendingCommands.removeWhere(
        (_, pending) => pending.matches(type, threadId: threadId),
      );
    }
    final readGeneration = type == 'thread.read'
        ? ++_timelineReadGeneration
        : null;
    final requestId = RelayProtocol.randomId('req');
    _outgoingSequence += 1;
    _pendingCommands[requestId] = _PendingCommand(
      kind: type,
      threadId: threadId,
      turnId: turnId,
      sentAt: DateTime.now(),
      refreshToken: refreshToken,
      timelineReadGeneration: readGeneration,
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
    return sent;
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
    String? timelineTimedOutSessionId;
    _pendingCommands.removeWhere((_, pending) {
      final expired = pending.sentAt.isBefore(cutoff);
      if (expired && pending.kind == 'thread.list') catalogTimedOut = true;
      if (expired &&
          pending.kind == 'thread.read' &&
          timelineLoading.value &&
          pending.threadId == _timelineLoadingSessionId) {
        timelineTimedOutSessionId = pending.threadId;
      }
      return expired;
    });
    if (catalogTimedOut && lastError.value.isEmpty) {
      lastError.value = '项目列表同步超时，请确认目标主机在线后重试。';
    }
    if (timelineTimedOutSessionId != null) {
      _failTimelineLoad(
        '任务对话加载超时（已等待 ${_commandTimeout.inSeconds} 秒），请检查 Relay 或目标主机后重试。',
        sessionId: timelineTimedOutSessionId,
      );
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

  /// Returns the parameter object carried by a Codex notification.
  ///
  /// The App Server protocol has used both `data` and `params`, while a few
  /// Relay builds wrapped the notification one additional time in `payload`
  /// or `notification`.  Keeping this compatibility logic here means the
  /// streaming handlers below always receive the same flat parameter map.
  Map<String, dynamic> _codexEventData(Map<String, dynamic> event) {
    var current = event;
    for (var depth = 0; depth < 3; depth += 1) {
      Map<String, dynamic>? next;
      for (final key in const ['data', 'params', 'payload', 'notification']) {
        final candidate = _asMap(current[key]);
        if (candidate != null) {
          next = candidate;
          break;
        }
      }
      if (next == null) break;
      current = next;
    }
    return current;
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

  DateTime? _dateTime(Object? value) {
    if (value is num) {
      final raw = value.toInt();
      final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds).toUtc();
    }
    final text = _readString(value);
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    final numeric = num.tryParse(text);
    if (numeric == null) return null;
    return _dateTime(numeric);
  }

  DateTime? _turnTimestamp(Map<String, dynamic> turn, String field) {
    final snakeCase = field.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
    return _dateTime(turn[field] ?? turn[snakeCase]);
  }

  String? _turnIdFromTurn(Map<String, dynamic> turn) {
    return _readString(turn['id']) ??
        _readString(turn['turnId']) ??
        _readString(turn['turn_id']);
  }

  int? _turnDurationMs(Map<String, dynamic> turn) {
    final value = turn['durationMs'] ?? turn['duration_ms'];
    final parsed = _readIntValue(value);
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  int? _durationBetween(DateTime? startedAt, DateTime? completedAt) {
    if (startedAt == null || completedAt == null) return null;
    final milliseconds = completedAt.difference(startedAt).inMilliseconds;
    return milliseconds >= 0 ? milliseconds : null;
  }

  List<SessionEvent> _applyTurnTiming(
    List<SessionEvent> source, {
    DateTime? startedAt,
    DateTime? completedAt,
    int? durationMs,
  }) {
    if (source.isEmpty) return const [];

    final resolvedStart =
        startedAt ??
        (completedAt != null && durationMs != null
            ? completedAt.subtract(Duration(milliseconds: durationMs))
            : null);
    final resolvedEnd =
        completedAt ??
        (startedAt != null && durationMs != null
            ? startedAt.add(Duration(milliseconds: durationMs))
            : null);
    final resolvedDuration =
        durationMs ?? _durationBetween(resolvedStart, resolvedEnd);
    final timed = List<SessionEvent>.of(source);
    if (resolvedStart != null) {
      timed[0] = timed[0].copyWith(time: resolvedStart);
    }
    if (resolvedEnd != null) {
      final lastIndex = timed.length - 1;
      timed[lastIndex] = timed[lastIndex].copyWith(time: resolvedEnd);
    }
    if (resolvedDuration != null) {
      final lastIndex = timed.length - 1;
      timed[lastIndex] = timed[lastIndex].copyWith(
        durationMs: resolvedDuration,
      );
    }
    return timed;
  }

  String _extractText(Map<String, dynamic> map) {
    for (final key in const [
      'delta',
      'textDelta',
      'text_delta',
      'deltaText',
      'delta_text',
      'contentDelta',
      'content_delta',
      'text',
      'message',
      'output',
      'summary',
      'content',
      'preview',
      'item',
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
    _finishTimelineRefresh(error: '任务刷新失败：Relay 连接已断开。');
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _finishHealthCheck('Relay 连接已断开，请重试。');
    connected.value = false;
    connectionLabel.value = 'offline';
    _clearRemoteModels();
    if (timelineLoading.value) {
      _failTimelineLoad('Relay 连接已断开，任务对话未加载完成，请重试。');
    }
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
    _finishTimelineRefresh(error: '任务刷新失败：Relay 连接异常，请重试。');
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _finishHealthCheck(_connectionTestError(error));
    connected.value = false;
    connectionLabel.value = 'failed';
    _clearRemoteModels();
    if (timelineLoading.value) {
      _failTimelineLoad('Relay 连接异常，任务对话加载失败，请重试。');
    }
    _fail(_connectionTestError(error));
    if (wasConnected &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
    _scheduleReconnect();
  }

  void _refreshLiveTimeline({bool force = false, int? refreshToken}) {
    if (!connected.value) return;
    final listSent = _sendCommand(
      'thread.list',
      {'limit': 100},
      force: force,
      refreshToken: refreshToken,
    );

    // A manual refresh always rehydrates the selected task. The periodic
    // refresh only reads detail while the selected task is active (or still
    // being hydrated), keeping completed histories from being downloaded
    // every two seconds.
    final selectedId = (selectedSessionId.value ?? _requestedEventsSessionId)
        ?.trim();
    if (selectedId == null || selectedId.isEmpty) {
      if (force && !listSent) {
        _finishTimelineRefresh(
          error: '任务刷新失败：当前 Relay 连接不可用，请重试。',
          token: refreshToken,
        );
      }
      return;
    }
    final selectedIsRunning = sessions.any(
      (session) => session.id.trim() == selectedId && session.isRunning,
    );
    final shouldRead =
        force ||
        timelineStatus.value.isActive ||
        timelineLoading.value ||
        selectedIsRunning;
    if (!shouldRead || (timelineLoadError.value.isNotEmpty && !force)) {
      return;
    }

    if (force) {
      _requestedEventsSessionId = selectedId;
      for (final session in sessions) {
        if (session.id.trim() == selectedId) {
          _requestedEventsPrompt = session.prompt;
          break;
        }
      }
      // Restart the hydration timeout for a failed/stale read without
      // clearing the transcript that is already visible on screen.
      _beginTimelineLoad(selectedId);
    }
    final readSent = _sendCommand(
      'thread.read',
      {},
      threadId: selectedId,
      force: force,
      refreshToken: refreshToken,
    );
    if (force && !listSent && !readSent) {
      _finishTimelineRefresh(
        error: '任务刷新失败：当前 Relay 连接不可用，请重试。',
        token: refreshToken,
      );
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
              timelineStatus.value.isActive) {
        continue;
      }
      final wasRunning =
          _shouldNotifyTerminalSession(session.id) ||
          session.id == currentSessionId.value && timelineStatus.value.isActive;
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
      _clearTimelineLoadState();
      selectedSessionId.value = null;
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      _setTimelineStatus(TimelineTaskStatus.unknown);
      if (events.isNotEmpty) {
        events.clear();
        _bumpTimelineRevision();
      }
      return;
    }

    final workspace = selectedWorkspace.value;
    final candidates = _timelineSessionCandidates(workspace);
    if (candidates.isEmpty) {
      _clearTimelineLoadState();
      selectedSessionId.value = null;
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      _setTimelineStatus(TimelineTaskStatus.unknown);
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
      _clearTimelineLoadState();
      currentSessionId.value = null;
      _setTimelineStatus(TimelineTaskStatus.unknown);
      return;
    }
    final selected = candidates.cast<SessionRecord?>().firstWhere(
      (session) => session?.id == selectedId,
      orElse: () => null,
    );
    if (selected == null) {
      _clearTimelineLoadState();
      selectedSessionId.value = null;
      _requestedEventsSessionId = null;
      _requestedEventsPrompt = null;
      currentSessionId.value = null;
      _setTimelineStatus(TimelineTaskStatus.unknown);
      return;
    }
    final latest = selected;
    final requestedRunning =
        _requestedEventsSessionId == latest.id && timelineStatus.value.isActive;
    if (latest.isRunning) {
      _markSessionRunningForNotification(latest.id);
      currentSessionId.value = latest.id;
      _setTimelineStatus(TimelineTaskStatus.processing);
    } else if (!requestedRunning &&
        _requestedEventsSessionId != latest.id &&
        !timelineStatus.value.isTerminal) {
      currentSessionId.value = null;
      _setTimelineStatus(TimelineTaskStatus.loading);
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
    if (!timelineStatus.value.isActive && !timelineStatus.value.isTerminal) {
      _setTimelineStatus(TimelineTaskStatus.loading);
    }
    _beginTimelineLoad(latest.id);
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
        durationMs: event.durationMs,
        usage: event.usage,
        attachments: event.attachments,
        itemId: event.itemId,
        turnId: event.turnId,
        isDelta: event.isDelta,
      );
    }
    // Empty deltas are lifecycle notifications, not visible transcript
    // content. Ignore them so a heartbeat cannot create blank answer cards.
    if (event.text.isEmpty &&
        event.attachments.isEmpty &&
        event.usage == null &&
        event.kind != 'running' &&
        event.kind != 'done' &&
        event.kind != 'interrupted') {
      return;
    }
    // Live stream events are valid content as well. If they arrive before a
    // pending thread.read response, stop showing the hydration spinner while
    // keeping the eventual read response free to merge historical events.
    if (timelineLoading.value) _finishTimelineLoad();
    if (event.kind == 'running') {
      final last = events.isEmpty ? null : events.last;
      if (last?.kind == 'running') {
        events[events.length - 1] = event;
        _bumpTimelineRevision();
        return;
      }
    }

    final existingIndex = _eventIdentityIndex(events, event);
    if (existingIndex >= 0) {
      final existing = events[existingIndex];
      final merged = event.isDelta
          ? _mergeDeltaEvent(existing, event)
          : _mergeSnapshotEvent(existing, event);
      if (!_sameTimelineEvent(existing, merged)) {
        events[existingIndex] = merged;
        _bumpTimelineRevision();
      }
      return;
    }
    // Older App Server builds omit itemId on streaming notifications. Keep
    // appending those fragments to the latest delta for the same turn so the
    // transcript still renders one continuously growing answer instead of a
    // new bubble for every network frame. A new non-delta snapshot remains a
    // separate item and cannot accidentally merge into this fallback.
    if (event.isDelta) {
      final fallbackIndex = _latestUnidentifiedDeltaIndex(event);
      if (fallbackIndex >= 0) {
        final existing = events[fallbackIndex];
        final merged = _mergeDeltaEvent(existing, event);
        if (!_sameTimelineEvent(existing, merged)) {
          events[fallbackIndex] = merged;
          _bumpTimelineRevision();
        }
        return;
      }
    }
    events.add(event);
    _bumpTimelineRevision();
  }

  int _latestUnidentifiedDeltaIndex(SessionEvent event) {
    final turnId = event.turnId?.trim() ?? '';
    for (var index = events.length - 1; index >= 0; index -= 1) {
      final candidate = events[index];
      // A running marker or a new user prompt starts a fresh turn. Do not
      // let a legacy unscoped delta from that turn merge into an older
      // answer merely because both items share the same kind.
      if (candidate.kind == 'running' || candidate.kind == 'user') break;
      if (!candidate.isDelta ||
          candidate.itemId?.trim().isNotEmpty == true ||
          candidate.kind != event.kind) {
        continue;
      }
      final candidateTurnId = candidate.turnId?.trim() ?? '';
      if (turnId.isNotEmpty &&
          candidateTurnId.isNotEmpty &&
          candidateTurnId != turnId) {
        continue;
      }
      return index;
    }
    return -1;
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
    if (events.isEmpty) return loadedEvents;
    final merged = List<SessionEvent>.of(loadedEvents);
    for (final event in events) {
      if (!_isLiveStatusEvent(event)) {
        continue;
      }
      final identityIndex = _eventIdentityIndex(merged, event);
      if (identityIndex >= 0) {
        // A thread.read snapshot can race a newer delta. Always merge the
        // locally accumulated value back into the snapshot instead of
        // replacing the live text with the older server response.
        merged[identityIndex] = _mergeSnapshotEvent(
          merged[identityIndex],
          event,
        );
        continue;
      }
      final similarIndex = _similarEventIndex(merged, event);
      if (similarIndex >= 0) {
        // Older servers omit itemId on deltas. Text containment is only a
        // fallback identity in that case; still merge the longer live value
        // instead of discarding it as a duplicate.
        merged[similarIndex] = _mergeSnapshotEvent(merged[similarIndex], event);
        continue;
      }
      merged.add(event);
    }
    return merged;
  }

  int _eventIdentityIndex(List<SessionEvent> source, SessionEvent event) {
    final itemId = event.itemId?.trim() ?? '';
    if (itemId.isEmpty) return -1;
    final turnId = event.turnId?.trim() ?? '';
    for (var index = 0; index < source.length; index += 1) {
      final candidate = source[index];
      if (candidate.itemId?.trim() != itemId || candidate.kind != event.kind) {
        continue;
      }
      final candidateTurnId = candidate.turnId?.trim() ?? '';
      if (turnId.isNotEmpty &&
          candidateTurnId.isNotEmpty &&
          turnId != candidateTurnId) {
        continue;
      }
      return index;
    }
    return -1;
  }

  SessionEvent _mergeDeltaEvent(SessionEvent existing, SessionEvent delta) {
    final nextText = _appendDeltaText(existing.text, delta.text);
    return existing.copyWith(
      text: nextText,
      time: existing.time ?? delta.time,
      durationMs: delta.durationMs ?? existing.durationMs,
      usage: delta.usage ?? existing.usage,
      attachments: _mergeEventAttachments(
        existing.attachments,
        delta.attachments,
      ),
      itemId: existing.itemId ?? delta.itemId,
      turnId: existing.turnId ?? delta.turnId,
      isDelta: true,
    );
  }

  SessionEvent _mergeSnapshotEvent(
    SessionEvent existing,
    SessionEvent snapshot,
  ) {
    final nextText = _preferSnapshotText(existing.text, snapshot.text);
    return existing.copyWith(
      text: nextText,
      time: existing.time ?? snapshot.time,
      durationMs: snapshot.durationMs ?? existing.durationMs,
      usage: snapshot.usage ?? existing.usage,
      attachments: _mergeEventAttachments(
        existing.attachments,
        snapshot.attachments,
      ),
      itemId: existing.itemId ?? snapshot.itemId,
      turnId: existing.turnId ?? snapshot.turnId,
      isDelta: existing.isDelta || snapshot.isDelta,
    );
  }

  String _appendDeltaText(String current, String delta) {
    if (delta.isEmpty) return current;
    if (current.isEmpty) return delta;
    // Some App Server releases call a cumulative text snapshot a "delta".
    // Treat it idempotently so reconnects do not duplicate the answer.
    if (current.endsWith(delta) || current == delta) return current;
    if (delta.startsWith(current)) return delta;
    if (current.contains(delta)) return current;
    return '$current$delta';
  }

  String _preferSnapshotText(String current, String snapshot) {
    if (snapshot.isEmpty) return current;
    if (current.isEmpty) return snapshot;
    if (snapshot.startsWith(current) || snapshot.length > current.length) {
      return snapshot;
    }
    if (current.startsWith(snapshot) || current.contains(snapshot)) {
      return current;
    }
    // A snapshot from the host is authoritative only when it is not older
    // than the local accumulated value. For unrelated text, retain the
    // longer value to protect a live stream from a stale read response.
    return snapshot.length >= current.length ? snapshot : current;
  }

  bool _sameTimelineEvent(SessionEvent a, SessionEvent b) {
    if (a.kind != b.kind ||
        a.text != b.text ||
        a.durationMs != b.durationMs ||
        a.itemId != b.itemId ||
        a.turnId != b.turnId ||
        a.isDelta != b.isDelta ||
        a.attachments.length != b.attachments.length) {
      return false;
    }
    for (var index = 0; index < a.attachments.length; index += 1) {
      final left = a.attachments[index];
      final right = b.attachments[index];
      if (left.type != right.type ||
          left.mime != right.mime ||
          left.dataUrl != right.dataUrl ||
          left.thumbnailDataUrl != right.thumbnailDataUrl ||
          left.resourceUrl != right.resourceUrl ||
          left.expiresAt != right.expiresAt) {
        return false;
      }
    }
    return true;
  }

  bool _isLiveStatusEvent(SessionEvent event) {
    return event.kind == 'running' ||
        event.kind == 'assistant' ||
        event.kind == 'reasoning' ||
        event.kind == 'tool_call' ||
        event.kind == 'file_change' ||
        event.kind == 'git_change' ||
        event.kind == 'event';
  }

  int _similarEventIndex(List<SessionEvent> source, SessionEvent event) {
    final text = event.text.trim();
    for (var index = 0; index < source.length; index += 1) {
      final candidate = source[index];
      if (candidate.kind != event.kind) continue;
      final candidateText = candidate.text.trim();
      if (candidateText == text) return index;
      // A persisted assistant/reasoning item is usually the aggregate of
      // several streamed deltas. Treat containment as the same event so a
      // periodic thread.read does not duplicate already-persisted output.
      if ((event.kind == 'assistant' || event.kind == 'reasoning') &&
          text.isNotEmpty &&
          candidateText.isNotEmpty) {
        if (candidateText.contains(text) || text.contains(candidateText)) {
          return index;
        }
      }
    }
    return -1;
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
      if (!_sameTimelineEvent(current[index], next[index])) return false;
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
    lastError.value = error is String ? error : _connectionTestError(error);
  }

  String _connectionTestError(Object error) {
    if (error is TimeoutException) {
      return '连接测试超时，请检查 Relay 地址和网络连接。';
    }
    if (error is SocketException) {
      return '无法连接 Relay，请检查地址和网络连接。';
    }
    final text = error.toString().replaceFirst(
      RegExp(r'^[A-Za-z_]\w*:\s*'),
      '',
    );
    return _friendlyRelayError('', text);
  }

  String _friendlyRelayError(String code, String message) {
    final normalized = '${code.trim()} ${message.trim()}'.toLowerCase();
    if (normalized.contains('connection limit exceeded') ||
        normalized.contains('connect token connection limit')) {
      return '连接令牌已达到并发连接上限，请断开其它连接或提高令牌的连接上限。';
    }
    if (code == 'auth.token_expired' ||
        normalized.contains('token expired') ||
        normalized.contains('token_expired')) {
      return '连接令牌已过期，请更新令牌后重试。';
    }
    if (code == 'auth.invalid_token' ||
        normalized.contains('invalid token') ||
        normalized.contains('token is invalid')) {
      return '连接令牌无效，请检查令牌是否正确。';
    }
    if (code == 'connection.revoked' ||
        normalized.contains('connection revoked')) {
      return '当前连接已被撤销，请重新创建或更新连接令牌。';
    }
    if (code == 'connection.rejected') {
      return 'Relay 拒绝了连接，请检查连接配置和令牌权限。';
    }
    if (message.trim().isEmpty) {
      return 'Relay 连接失败，请检查连接配置后重试。';
    }
    // Keep useful localised protocol errors while avoiding raw English Relay
    // diagnostics in the UI.
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(message)) return message;
    return 'Relay 连接失败，请检查连接配置后重试。';
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
    this.turnId,
    this.refreshToken,
    this.timelineReadGeneration,
  });

  final String kind;
  final String? threadId;
  final String? turnId;
  final DateTime sentAt;
  final int? refreshToken;
  final int? timelineReadGeneration;

  bool matches(String commandKind, {String? threadId}) {
    return kind == commandKind && this.threadId == threadId;
  }
}
