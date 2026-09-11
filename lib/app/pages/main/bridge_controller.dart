import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../models/bridge_models.dart';
import '../../models/pending_interaction.dart';
import '../../services/event_recovery.dart';
import '../../services/answer_metadata.dart';
import '../../services/context_window_usage.dart';
import '../../services/relay_protocol.dart';
import '../../services/turn_file_changes.dart';
import '../../services/timeline_events.dart';
import '../../services/session_cache.dart';
import '../../services/usage_statistics.dart';
import '../../services/task_notification_controller.dart';
import '../settings/settings_preferences_controller.dart';

class BridgeController extends GetxController {
  static const _storageContainer = 'recodex';
  static const _commandTimeout = Duration(seconds: 35);
  static const _tokenRefreshLead = Duration(minutes: 1);
  static const _unknownTokenRefreshInterval = Duration(minutes: 5);
  static const _tokenRefreshRetry = Duration(seconds: 15);
  // These are fallback reconciliation intervals. Normal streaming updates
  // arrive from the Relay event channel; the shorter intervals close the
  // recovery window when a desktop-owned thread cannot be resumed.
  static const _liveTimelineInterval = Duration(seconds: 2);
  static const _catalogRefreshInterval = Duration(seconds: 15);
  static const _activeTimelineReadInterval = Duration(seconds: 5);
  static const _cacheWriteDebounce = Duration(milliseconds: 250);
  // Keep the live transcript bounded. Full history remains available in the
  // persistent SessionCache and is loaded on demand when a task is selected.
  static const _maxInMemoryTimelineEvents = 500;
  static const _maxInMemoryTimelineThreads = 5;
  static const _maxInMemoryEventTextChars = 1_000_000;
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
  final pendingInteractions = <String, PendingInteraction>{}.obs;
  final submittedInteractions = <String>{}.obs;
  final interactionNotice = ''.obs;
  final backendReady = true.obs;
  int _interactionRevision = 0;
  final _eventRecovery = EventRecovery();
  List<PendingInteraction> get selectedInteractions => pendingInteractions
      .values
      .where((item) => item.threadId == selectedSessionId.value)
      .toList();
  final connected = false.obs;
  final busy = false.obs;

  /// Saved Relay connections.  The active profile is mirrored into the
  /// connection observables below so existing screens can keep reacting to
  /// the same data flow.
  final pairings = <PairingProfile>[].obs;
  final activePairingId = RxnString();

  final workspaces = <WorkspaceInfo>[].obs;
  final sessions = <SessionRecord>[].obs;
  final _officialWorkspaces = <WorkspaceInfo>[];
  final events = <SessionEvent>[].obs;
  final selectedWorkspace = Rxn<WorkspaceInfo>();

  /// The task currently shown in the main conversation view. This is kept
  /// separate from [currentSessionId], which is also used for an active turn.
  final selectedSessionId = RxnString();
  final gitSnapshot = Rxn<GitSnapshot>();
  final composerContext = ComposerContext.fallback.obs;
  ContextWindowUsage? get contextWindowUsage =>
      latestContextWindowUsage(events);
  final permissionMode = '默认权限'.obs;
  final currentSessionId = RxnString();
  final _threadComposerSettings = <String, Map<String, dynamic>>{};
  final _deferredComposerSends = <String, Object>{};

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

  /// Cache-first state exposed to the UI. A stale cache is still useful and
  /// should remain visible while the Relay performs the next authoritative
  /// reconciliation.
  final cacheHydrating = false.obs;
  final cacheStale = false.obs;
  final cacheLastUpdated = Rxn<DateTime>();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _liveTimelineTimer;
  Timer? _catalogRefreshTimer;
  Timer? _cacheWriteTimer;
  Timer? _handshakeTimer;
  Timer? _heartbeatTimer;
  Timer? _healthCheckTimer;
  Timer? _timelineLoadTimer;
  Timer? _timelineLoadTimeoutTimer;
  Timer? _timelineStatusTimer;
  Timer? _timelineRefreshTimeoutTimer;
  Timer? _tokenRefreshTimer;
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
  Future<void>? _tokenRefreshInFlight;
  bool _credentialRefreshBlocked = false;
  bool _tokenRotationInProgress = false;
  int _tokenRefreshRetryAttempt = 0;
  int _connectionAttempt = 0;
  int _reconnectAttemptCount = 0;
  String? _tokenRefreshContextKey;
  final _pendingCommands = <String, _PendingCommand>{};
  String? _timelineSnapshotHash;
  String? _timelineSnapshotHashSessionId;
  DateTime? _timelineSnapshotHashReceivedAt;
  final _seenIncomingMessageIds = <String>{};
  // A Relay connection is at-least-once. Keep a single recovery request in
  // flight when an incoming event sequence has a gap; otherwise advancing the
  // cursor before replay would permanently skip the missing events.
  bool _syncRecoveryInFlight = false;
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
  final _timelineSnapshotGuard = TimelineSnapshotGuard();
  bool _sessionRestoreAttempted = false;
  final _sessionLifecycles = <String, _SessionLifecycle>{};
  final _notifiedTerminalSessions = <String>{};
  final SessionCache _sessionCache = SessionCache();
  SessionCacheScope? _cacheScope;
  String? _cacheLoadedScopeKey;
  int _cacheGeneration = 0;
  Future<void>? _cacheLoadInFlight;
  final _timelineMemoryCache = <String, List<SessionEvent>>{};
  final _timelineMemoryCacheAccess = <String, int>{};
  int _timelineMemoryCacheClock = 0;
  final _pendingTimelineCacheWrites = <String, List<SessionEvent>>{};
  final _pendingTimelineCacheReplacements = <String>{};
  bool _pendingCatalogCacheWrite = false;
  int? _pendingCacheSequence;
  DateTime? _pendingCacheSyncedAt;
  Future<void>? _cacheFlushInFlight;
  bool _cacheFlushRequested = false;
  DateTime? _lastTimelineReadRequestedAt;

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
    // Credentials are loaded asynchronously; [_loadStoredCredentials] will
    // activate the scope again once the selected pairing is known.
    unawaited(_activateSessionCache());
  }

  @override
  void onClose() {
    stopLiveTimelineRefresh();
    _catalogRefreshTimer?.cancel();
    _catalogRefreshTimer = null;
    _cacheWriteTimer?.cancel();
    _cacheWriteTimer = null;
    _timelineStatusTimer?.cancel();
    _timelineStatusTimer = null;
    _finishTimelineRefresh();
    _clearTimelineLoadState();
    unawaited(() async {
      await _flushCacheWrites();
      await _sessionCache.close();
    }());
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
    _eventRecovery.reset();
    pendingInteractions.clear();
    submittedInteractions.clear();
    interactionNotice.value = '';
    backendReady.value = true;
    _finishTimelineRefresh();
    _clearTimelineLoadState();
    lastError.value = '';
    workspaces.clear();
    _officialWorkspaces.clear();
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
    _timelineSnapshotGuard.reset();
    _pendingHelloRequestId = null;
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    _pendingCommands.clear();
    _seenIncomingMessageIds.clear();
    _sessionLifecycles.clear();
    _notifiedTerminalSessions.clear();
    _sessionRestoreAttempted = false;
    _timelineMemoryCache.clear();
    _timelineMemoryCacheAccess.clear();
    _timelineMemoryCacheClock = 0;
    _pendingTimelineCacheWrites.clear();
    _pendingTimelineCacheReplacements.clear();
    _pendingCatalogCacheWrite = false;
    _pendingCacheSequence = null;
    _pendingCacheSyncedAt = null;
    _cacheFlushRequested = false;
    _cacheWriteTimer?.cancel();
    _cacheWriteTimer = null;
    _cacheScope = null;
    _cacheLoadedScopeKey = null;
    _cacheGeneration += 1;
    cacheHydrating.value = false;
    cacheStale.value = false;
    cacheLastUpdated.value = null;
    unawaited(_activateSessionCache());
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
    bool fromReconnect = false,
  }) async {
    await _ensureCredentialsLoaded();
    final attempt = ++_connectionAttempt;
    // A new explicit connection attempt supersedes any rotation cleanup that
    // may still be waiting on a platform WebSocket close callback.
    _tokenRotationInProgress = false;
    final previousToken = pairingToken.value;
    final previousGrant = endpointGrant.value;
    final trimmedToken = token.trim();
    final trimmedGrant = inputEndpointGrant?.trim();
    final credentialsChanged =
        (trimmedToken.isNotEmpty && trimmedToken != previousToken) ||
        (trimmedGrant != null && trimmedGrant != previousGrant);
    _manualDisconnect = false;
    if (!fromReconnect || credentialsChanged) {
      _credentialRefreshBlocked = false;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    busy.value = true;
    lastError.value = '';
    connectionLabel.value = 'connecting';

    try {
      await _closeSocket();
      if (!_isCurrentConnectionAttempt(attempt)) return;
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
      // Keep the historical connect() contract: an omitted/blank token means
      // "reuse the configured token".  Grant-only pairings already have an
      // empty observable token, while reconnects must not erase a still-valid
      // token merely because the caller did not repeat it.
      if (trimmedToken.isNotEmpty && trimmedToken != previousToken) {
        tokenExpiresAt.value = 0;
        _forceTokenRefresh = false;
        if (inputEndpointGrant == null) {
          // An explicitly replaced Token is not proof that it belongs to the
          // previously paired Endpoint. Do not silently combine it with the
          // old proof-bound Grant: that could mint a token for the old
          // pairing and make the user's newly pasted Token appear to be
          // ignored. Callers that intentionally rotate only the Token while
          // retaining its Grant must pass the Grant explicitly.
          endpointGrant.value = '';
          grantExpiresAt.value = 0;
        }
      }
      if (trimmedToken.isNotEmpty) pairingToken.value = trimmedToken;
      if (inputEndpointGrant != null) {
        if (trimmedGrant != previousGrant) {
          grantExpiresAt.value = 0;
        }
        endpointGrant.value = trimmedGrant ?? '';
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
      if (!_isCurrentConnectionAttempt(attempt)) return;
      endpointPublicKey.value = await RelayProtocol.publicKey(_keyPair!);
      final connectToken = await _usableConnectToken(
        trimmedToken,
        attempt: attempt,
      );
      if (!_isCurrentConnectionAttempt(attempt)) return;
      final socket = await WebSocket.connect(baseUrl.value);
      if (!_isCurrentConnectionAttempt(attempt)) {
        await _closeSocketInstance(socket);
        return;
      }
      _socket = socket;
      _socketSubscription = socket.listen(
        (raw) {
          if (_isCurrentSocket(socket, attempt)) _handleRawMessage(raw);
        },
        onDone: () {
          if (_isCurrentSocket(socket, attempt)) {
            _handleDone(socket: socket, attempt: attempt);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_isCurrentSocket(socket, attempt)) {
            _handleSocketError(error, socket: socket, attempt: attempt);
          }
        },
        cancelOnError: false,
      );
      final keyPair = _keyPair!;
      final hello = await RelayProtocol.connectHello(
        keyPair: keyPair,
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
      if (!_isCurrentConnectionAttempt(attempt)) {
        await _closeSocketInstance(socket);
        return;
      }
      _pendingHelloRequestId = hello['requestId'] as String?;
      socket.add(jsonEncode(hello));
      connectionLabel.value = 'auth';
      _handshakeTimer?.cancel();
      _handshakeTimer = Timer(const Duration(seconds: 10), () {
        if (!connected.value && connectionLabel.value == 'auth') {
          _fail(StateError('Relay 认证超时'));
          unawaited(_closeSocket());
          _scheduleReconnect();
        }
      });
      unawaited(_storeConnectionHints(expectedAttempt: attempt));
    } catch (error) {
      if (!_isCurrentConnectionAttempt(attempt)) return;
      _fail(_connectionTestError(error));
      connectionLabel.value = 'failed';
      connected.value = false;
      if (_isTerminalRefreshFailure(error) ||
          error.toString().toLowerCase().contains('auth.grant_required')) {
        _credentialRefreshBlocked = true;
        _forceTokenRefresh = false;
        _tokenRefreshTimer?.cancel();
        _tokenRefreshTimer = null;
      } else {
        _scheduleReconnect();
      }
    } finally {
      if (attempt == _connectionAttempt) busy.value = false;
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
    String inputEndpointGrant = '',
    int inputTokenExpiresAt = 0,
    int inputGrantExpiresAt = 0,
  }) async {
    try {
      final normalizedBaseUrl = _normalizeRelayUrl(inputBaseUrl);
      final nextSpaceId = inputSpaceId.trim();
      final nextTargetDeviceId = inputTargetDeviceId.trim();
      final nextEndpointId = inputEndpointId.trim();
      final nextEndpointType = inputEndpointType.trim().isEmpty
          ? 'app'
          : inputEndpointType.trim();
      var connectToken = token.trim();
      final draftGrant = inputEndpointGrant.trim();
      final encodedKey = inputDeviceKey.trim();
      if (nextSpaceId.isEmpty ||
          nextTargetDeviceId.isEmpty ||
          nextEndpointId.isEmpty) {
        return '请先填写空间 ID、目标主机接入端 ID 和本机接入端 ID。';
      }
      if (connectToken.isEmpty && draftGrant.isEmpty) {
        return '请填写连接令牌或接入端授权凭证。';
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
        endpointGrant: draftGrant,
        spaceId: nextSpaceId,
        targetDeviceId: nextTargetDeviceId,
        endpointId: nextEndpointId,
        endpointType: nextEndpointType,
        deviceKey: encodedKey,
      )) {
        return await checkCurrentConnection();
      }

      final keyPair = await RelayProtocol.keyPairFromSeed(
        RelayProtocol.decodeBase64Url(encodedKey),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final normalizedTokenExpiresAt = inputTokenExpiresAt > 0
          ? inputTokenExpiresAt
          : 0;
      final normalizedGrantExpiresAt = inputGrantExpiresAt > 0
          ? inputGrantExpiresAt
          : 0;
      final shouldRefreshBeforeHandshake =
          draftGrant.isNotEmpty &&
          (connectToken.isEmpty ||
              normalizedTokenExpiresAt <= 0 ||
              normalizedTokenExpiresAt <=
                  now + _tokenRefreshLead.inMilliseconds ||
              normalizedGrantExpiresAt > 0 &&
                  normalizedGrantExpiresAt <=
                      now + _tokenRefreshLead.inMilliseconds);

      // A Grant-only draft, or a draft whose token expiry is unknown/stale,
      // should be tested with a freshly minted token. This avoids reporting a
      // false failure merely because an editor still shows yesterday's token.
      if (shouldRefreshBeforeHandshake) {
        final refreshed = await _requestConnectToken(
          relay: Uri.parse(normalizedBaseUrl),
          keyPair: keyPair,
          grant: draftGrant,
          expectedSpaceId: nextSpaceId,
          expectedEndpointId: nextEndpointId,
          expectedEndpointType: nextEndpointType,
        );
        connectToken = refreshed.token;
      }

      var refreshAttempted = shouldRefreshBeforeHandshake;
      while (true) {
        final attempt = await _testConnectionHandshake(
          relayUrl: normalizedBaseUrl,
          keyPair: keyPair,
          token: connectToken,
          deviceName: inputDeviceName,
          spaceId: nextSpaceId,
          endpointId: nextEndpointId,
          endpointType: nextEndpointType,
        );
        if (attempt.error == null) return null;
        if (!refreshAttempted &&
            draftGrant.isNotEmpty &&
            _isRefreshableRelayCode(attempt.code ?? '')) {
          // Relay is authoritative when expiry metadata is missing or stale.
          // Retry exactly once with the proof-bound Grant, then surface the
          // server's friendly error instead of looping indefinitely.
          final refreshed = await _requestConnectToken(
            relay: Uri.parse(normalizedBaseUrl),
            keyPair: keyPair,
            grant: draftGrant,
            expectedSpaceId: nextSpaceId,
            expectedEndpointId: nextEndpointId,
            expectedEndpointType: nextEndpointType,
          );
          connectToken = refreshed.token;
          refreshAttempted = true;
          continue;
        }
        return attempt.error;
      }
    } catch (error) {
      return _connectionTestError(error);
    }
  }

  /// Performs one isolated authentication handshake for [testConnection].
  /// The returned code lets the caller distinguish a stale Connect Token from
  /// transport/protocol failures without exposing raw credential material.
  Future<_ConnectionTestAttempt> _testConnectionHandshake({
    required String relayUrl,
    required SimpleKeyPair keyPair,
    required String token,
    required String deviceName,
    required String spaceId,
    required String endpointId,
    required String endpointType,
  }) async {
    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    Timer? timeout;
    final result = Completer<_ConnectionTestAttempt>();

    void complete(_ConnectionTestAttempt attempt) {
      if (!result.isCompleted) result.complete(attempt);
    }

    try {
      socket = await WebSocket.connect(
        relayUrl,
      ).timeout(const Duration(seconds: 10));
      subscription = socket.listen(
        (raw) {
          try {
            final decoded = _decodeTextMessage(raw);
            final type = decoded['type'] as String? ?? '';
            if (type == 'relay.error') {
              final code = decoded['code'] as String? ?? 'relay.error';
              final message = decoded['message'] as String? ?? 'Relay 拒绝了连接';
              complete(
                _ConnectionTestAttempt(
                  error: _friendlyRelayError(code, message),
                  code: code,
                ),
              );
              return;
            }
            if (type != 'connect.welcome') return;
            RelayProtocol.validateWelcome(decoded);
            if (decoded['spaceId'] != spaceId ||
                decoded['endpointId'] != endpointId) {
              complete(
                const _ConnectionTestAttempt(
                  error: 'Relay 返回的空间 ID 或接入端 ID 与当前配置不一致。',
                ),
              );
              return;
            }
            complete(const _ConnectionTestAttempt());
          } catch (error) {
            complete(
              _ConnectionTestAttempt(error: _connectionTestError(error)),
            );
          }
        },
        onError: (Object error) => complete(
          _ConnectionTestAttempt(error: _connectionTestError(error)),
        ),
        onDone: () =>
            complete(const _ConnectionTestAttempt(error: 'Relay 在认证完成前关闭了连接。')),
        cancelOnError: false,
      );
      final hello = await RelayProtocol.connectHello(
        keyPair: keyPair,
        spaceId: spaceId,
        endpointId: endpointId,
        endpointType: endpointType,
        endpointName: deviceName.trim().isEmpty
            ? 'Flutter phone'
            : deviceName.trim(),
        token: token,
        test: true,
      );
      socket.add(jsonEncode(hello));
      timeout = Timer(const Duration(seconds: 10), () {
        complete(
          const _ConnectionTestAttempt(error: 'Relay 认证超时，请检查地址、令牌和网络连接。'),
        );
      });
      return await result.future;
    } catch (error) {
      return _ConnectionTestAttempt(error: _connectionTestError(error));
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
    required String endpointGrant,
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
        endpointGrant == this.endpointGrant.value &&
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
    _connectionAttempt += 1;
    _manualDisconnect = true;
    _finishTimelineRefresh();
    _clearTimelineLoadState();
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _tokenRotationInProgress = false;
    _credentialRefreshBlocked = false;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _finishHealthCheck('Relay 连接已断开。');
    await _closeSocket();
    connected.value = false;
    connectionLabel.value = 'offline';
    cacheStale.value = true;
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
    _timelineSnapshotHash = null;
    _timelineSnapshotHashSessionId = null;
    _timelineSnapshotHashReceivedAt = null;
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

  int _beginTimelineRefresh({String timeoutMessage = '任务刷新超时，请确认目标主机在线后重试。'}) {
    _timelineRefreshTimeoutTimer?.cancel();
    final token = ++_timelineRefreshToken;
    _activeTimelineRefreshToken = token;
    timelineRefreshing.value = true;
    if (lastError.value.startsWith('任务刷新') ||
        lastError.value.startsWith('项目刷新') ||
        lastError.value.startsWith('刷新失败')) {
      lastError.value = '';
    }
    _timelineRefreshTimeoutTimer = Timer(_commandTimeout, () {
      if (_activeTimelineRefreshToken != token) return;
      _finishTimelineRefresh(error: timeoutMessage);
    });
    return token;
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
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _finishTimelineRefresh();
    _finishHealthCheck('Relay 连接已断开。');
    _currentTurnStartedAt = null;
    try {
      await subscription?.cancel().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {
      // Continue closing the underlying socket even if a stream controller
      // reports an error while the connection is being replaced.
    }
    await _closeSocketInstance(socket);
  }

  Future<void> _closeSocketForRotation(WebSocket? socket) async {
    if (socket != null && identical(_socket, socket)) {
      await _closeSocket();
    } else if (socket != null) {
      await _closeSocketInstance(socket);
    } else if (_socket != null) {
      await _closeSocket();
    }
  }

  Future<void> _closeSocketInstance(WebSocket? socket) async {
    if (socket == null || socket.readyState == WebSocket.closed) return;
    try {
      await socket.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {
      // A stale/platform socket must never block a new connection attempt.
    }
  }

  bool _isCurrentSocket(WebSocket socket, int attempt) {
    return identical(_socket, socket) && attempt == _connectionAttempt;
  }

  void selectWorkspace(WorkspaceInfo? workspace) {
    if (backendReady.value) interactionNotice.value = '';
    _clearTimelineLoadState();
    selectedWorkspace.value = workspace;
    unawaited(_storeSelectedWorkspace(workspace));
    gitSnapshot.value = null;
    currentSessionId.value = null;
    selectedSessionId.value = null;
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _timelineSnapshotGuard.reset();
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
    if (backendReady.value) interactionNotice.value = '';
    if (session.id.trim().isEmpty) return;

    final previousSessionId = selectedSessionId.value?.trim();
    if (previousSessionId != null && previousSessionId != session.id.trim()) {
      _rememberVisibleTimeline();
    }
    _clearTimelineLoadState();

    final workspace = _workspaceForSession(session);
    if (workspace != null &&
        !_sameWorkspace(selectedWorkspace.value, workspace)) {
      selectedWorkspace.value = workspace;
      unawaited(_storeSelectedWorkspace(workspace));
      gitSnapshot.value = null;
      refreshContext();
      gitStatus(includeDiff: true);
    }

    gitSnapshot.value = null;
    selectedSessionId.value = session.id;
    currentSessionId.value = session.id;
    _showThreadComposerSettings(session.id);
    // A selected task may have a different latest turn than the task that was
    // visible before it. Do not let a delayed terminal event from the old
    // task pass the turn guard while the new thread.read is in flight.
    _currentTurnId = null;
    _lastTerminalTurnId = null;
    _currentTurnStartedAt = null;
    _timelineSnapshotGuard.reset();
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
    final cachedEvents = _readTimelineMemory(_timelineCacheKey(session.id));
    if (previousSessionId == session.id.trim() ||
        cachedEvents == null ||
        cachedEvents.isEmpty) {
      if (previousSessionId != session.id.trim() && events.isNotEmpty) {
        events.clear();
        _bumpTimelineRevision();
      }
      _beginTimelineLoad(session.id);
    } else {
      events.assignAll(_boundedInMemoryEvents(cachedEvents));
      _bumpTimelineRevision();
      _finishTimelineLoad(sessionId: session.id);
    }
    unawaited(_loadCachedTimeline(session.id));

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
    _timelineSnapshotGuard.reset();
    timelineTurnStartedAt.value = null;
    _setTimelineStatus(
      selected?.isRunning == true
          ? TimelineTaskStatus.processing
          : TimelineTaskStatus.loading,
    );
    if (selected?.isRunning == true) {
      _markSessionRunningForNotification(selectedId);
    }
    _rememberVisibleTimeline();
    if (events.isEmpty) {
      _beginTimelineLoad(selectedId);
    } else {
      // Keep the last visible transcript while the forced read reconciles it.
      _finishTimelineLoad(sessionId: selectedId);
    }
    unawaited(_loadCachedTimeline(selectedId));
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
    if (backendReady.value) interactionNotice.value = '';
    _rememberVisibleTimeline();
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
    _timelineSnapshotGuard.reset();
    _requestedEventsSessionId = null;
    _requestedEventsPrompt = null;
    _sessionRestoreAttempted = true;
    events.clear();
    _bumpTimelineRevision();
    if (Get.isRegistered<SettingsPreferencesController>()) {
      applyTaskPreferences(Get.find<SettingsPreferencesController>());
    }
  }

  void startSession(String prompt) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) return;

    // The composer is shared by both the "new conversation" state and an
    // already selected task.  A selected task must keep its identity: the
    // App Server creates a new thread only for an explicit new-conversation
    // action.  Clearing selectedSessionId here used to make every follow-up
    // message look like a fresh task and was the reason phone messages were
    // missing from the task open on the desktop.
    final selectedId = selectedSessionId.value?.trim() ?? '';
    if (selectedId.isNotEmpty && !_pendingSessionStart) {
      _appendSessionEvent(SessionEvent(kind: 'user', text: trimmedPrompt));
      currentSessionId.value = selectedId;
      _currentTurnId = null;
      _lastTerminalTurnId = null;
      _currentTurnStartedAt = null;
      _setTimelineStatus(TimelineTaskStatus.processing);
      _interruptRequested = false;
      _pendingPrompt = null;
      _sessionRestoreAttempted = true;
      _markSessionRunningForNotification(selectedId);
      _appendSessionEvent(
        const SessionEvent(kind: 'running', text: '正在继续 Codex 任务...'),
      );
      if (!_sendTurnStart(trimmedPrompt, threadId: selectedId)) {
        _finishCurrentSession(
          status: TaskNotificationStatus.failed,
          sessionId: selectedId,
          message: 'Relay 连接已断开，消息未发送。请连接后重试。',
        );
      }
      return;
    }

    _appendSessionEvent(SessionEvent(kind: 'user', text: trimmedPrompt));
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
    final sent = _sendCommand('thread.create', {
      if (workspace.path.trim().isNotEmpty) 'cwd': workspace.path,
    });
    if (!sent) {
      _pendingSessionStart = false;
      _pendingPrompt = null;
      _finishCurrentSession(
        status: TaskNotificationStatus.failed,
        message: 'Relay 连接已断开，消息未发送。请连接后重试。',
      );
    }
  }

  bool _sendTurnStart(String prompt, {required String threadId}) {
    if (!connected.value) return false;
    final waiting = _pendingCommands.values
        .where(
          (p) => p.kind == 'thread.settings.update' && p.threadId == threadId,
        )
        .map((p) => p.completion!.future)
        .toList();
    final command = <String, dynamic>{
      'text': prompt,
      if ((selectedWorkspace.value?.path ?? '').trim().isNotEmpty)
        'cwd': selectedWorkspace.value!.path,
    };
    if (waiting.isEmpty) {
      // The shared thread is authoritative. Echoing a cached model/effort
      // here would overwrite a desktop edit that is still crossing Relay.
      return _sendCommand('turn.start', command, threadId: threadId);
    }
    final sendToken = Object();
    _deferredComposerSends[threadId] = sendToken;
    unawaited(() async {
      final accepted = await Future.wait(
        waiting,
      ).timeout(_commandTimeout, onTimeout: () => [false]);
      if (_deferredComposerSends[threadId] != sendToken) return;
      _deferredComposerSends.remove(threadId);
      if (accepted.every((value) => value) && connected.value) {
        if (_sendCommand('turn.start', command, threadId: threadId)) return;
      }
      lastError.value = '任务设置未同步成功，消息未发送。请核对设置后重新发送。';
      _sessionLifecycles[threadId]?.visibleRunning = false;
      if (selectedSessionId.value == threadId) {
        _setTimelineStatus(TimelineTaskStatus.unknown);
        _reconcileSelectedTask();
      }
    }());
    return true;
  }

  bool _canEditComposer() {
    final id = _composerSettingsThreadId();
    if (id == null) return true;
    if (connected.value) {
      if (_threadComposerSettings.containsKey(id)) return true;
      lastError.value = '正在同步此任务的设置，请稍后重试。';
      return false;
    }
    lastError.value = '尚未连接 Relay，连接后才能修改此任务的设置。';
    return false;
  }

  void setComposerModel(String model) {
    final context = composerContext.value;
    if (model == context.model ||
        !context.models.contains(model) ||
        !_canEditComposer()) {
      return;
    }
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
    _sendComposerSettings({
      'model': model,
      if (effort.isNotEmpty) 'effort': effort,
    });
  }

  void setReasoningEffort(String effort) {
    final context = composerContext.value;
    if (effort == context.reasoningEffort ||
        !context.reasoningEfforts.contains(effort) ||
        !_canEditComposer()) {
      return;
    }
    composerContext.value = context.copyWith(reasoningEffort: effort);
    _sendComposerSettings({'effort': effort});
  }

  void setPermissionMode(String mode) {
    if (!['默认权限', '自动审查', '完全访问权限', '只读权限'].contains(mode) ||
        permissionMode.value == mode ||
        !_canEditComposer()) {
      return;
    }
    permissionMode.value = mode;
    composerContext.value = composerContext.value.copyWith(
      approvalPolicy: _approvalPolicyFor(mode),
    );
    _sendComposerSettings({'permissionMode': mode});
  }

  String? _composerSettingsThreadId() {
    final id = selectedSessionId.value?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  bool _sendComposerSettings(Map<String, dynamic> patch, {String? threadId}) {
    final id = threadId ?? _composerSettingsThreadId();
    if (id == null) {
      return true; // A new draft is applied once its thread exists.
    }
    final sent = _sendCommand(
      'thread.settings.update',
      patch,
      threadId: id,
      completion: Completer<bool>(),
    );
    if (!sent) {
      _showThreadComposerSettings(id);
      lastError.value = '任务设置未发送，请连接 Relay 后重试。';
    }
    if (sent) _showThreadComposerSettings(id);
    return sent;
  }

  void _applyThreadComposerSettings(String? threadId, Object? value) {
    final map = _asMap(value);
    final id =
        threadId ??
        _readString(map?['threadId']) ??
        _readString(_asMap(map?['thread'])?['id']);
    final raw = _asMap(map?['threadSettings']) ?? map;
    if (id == null || id.isEmpty || raw == null || raw['model'] is! String) {
      return;
    }
    final previous = _threadComposerSettings[id];
    final revision = raw['revision'];
    if (revision is num &&
        previous?['revision'] is num &&
        revision < (previous!['revision'] as num)) {
      _showThreadComposerSettings(id);
      return;
    }
    _threadComposerSettings.remove(id);
    _threadComposerSettings[id] = Map<String, dynamic>.from(raw);
    while (_threadComposerSettings.length > 256) {
      _threadComposerSettings.remove(_threadComposerSettings.keys.first);
    }
    _showThreadComposerSettings(id);
  }

  void _showThreadComposerSettings(String id) {
    if (selectedSessionId.value != id) return;
    final saved = _threadComposerSettings[id];
    if (saved == null) return;
    final raw = <String, dynamic>{...saved};
    // Keep newer local choices visible while older acknowledgements arrive.
    for (final pending in _pendingCommands.values) {
      if (pending.kind == 'thread.settings.update' && pending.threadId == id) {
        raw.addAll(pending.composerPatch ?? const {});
      }
    }
    final context = composerContext.value;
    final model = _readString(raw['model']) ?? context.model;
    final efforts = context.modelReasoningEfforts[model] ?? const <String>[];
    final effort =
        _readString(raw['effort'] ?? raw['reasoningEffort']) ??
        context.modelDefaultReasoningEfforts[model] ??
        '';
    composerContext.value = context.copyWith(
      model: model,
      reasoningEffort: effort,
      reasoningEfforts: efforts,
      approvalPolicy:
          _readString(raw['approvalPolicy']) ?? context.approvalPolicy,
    );
    permissionMode.value = _permissionModeFromSettings(raw);
  }

  String _permissionModeFromSettings(Map<String, dynamic> raw) {
    if (raw['permissionMode'] is String) return raw['permissionMode'] as String;
    final profile = _asMap(raw['activePermissionProfile']);
    final profileId =
        _readString(profile?['id']) ?? _readString(raw['permissions']);
    final sandbox = _asMap(raw['sandboxPolicy'] ?? raw['sandbox']);
    final sandboxType = _readString(sandbox?['type']);
    final reviewer = _readString(raw['approvalsReviewer']);
    final policy = raw['approvalPolicy'];
    if (profileId != null && !profileId.startsWith(':')) {
      return '自定义权限（$profileId）';
    }
    if ((profileId == ':danger-full-access' ||
            sandboxType == 'dangerFullAccess') &&
        policy == 'never') {
      return '完全访问权限';
    }
    if (profileId == ':read-only' || sandboxType == 'readOnly') return '只读权限';
    if (policy == 'on-request' &&
        (profileId == ':workspace' || sandboxType == 'workspaceWrite')) {
      if (reviewer == 'auto_review' || reviewer == 'guardian_subagent') {
        return '自动审查';
      }
      if (reviewer == null || reviewer == 'user') return '默认权限';
    }
    return '自定义权限';
  }

  /// Applies task defaults loaded from the settings page to the active
  /// composer. The remote host may still provide its own capability list;
  /// these values only select the user's preferred defaults.
  void applyTaskPreferences(SettingsPreferencesController preferences) {
    if (_composerSettingsThreadId() != null) {
      composerContext.value = composerContext.value.copyWith(
        requireConfirmGitWrite: preferences.confirmSensitiveActions.value,
      );
      return;
    }
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
    if (_deferredComposerSends.remove(sessionId) != null) {
      _sessionLifecycles[sessionId]?.visibleRunning = false;
      _setTimelineStatus(TimelineTaskStatus.interrupted);
      _appendSessionEvent(
        const SessionEvent(kind: 'interrupted', text: '已取消发送。'),
      );
      return;
    }
    final turnId = _currentTurnId;
    if (turnId == null || turnId.isEmpty) {
      _interruptRequested = true;
      return;
    }
    if (_pendingCommands.values.any(
      (p) =>
          p.kind == 'turn.interrupt' &&
          p.threadId == sessionId &&
          p.turnId == turnId,
    )) {
      return;
    }
    if (_sendCommand(
      'turn.interrupt',
      {},
      threadId: sessionId,
      turnId: turnId,
    )) {
      interactionNotice.value = '正在请求停止当前轮次…';
    }
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
    if (_pendingCommands.values.any(
      (p) =>
          p.kind == 'turn.interrupt' &&
          p.threadId == sessionId &&
          p.turnId == turnId,
    )) {
      return;
    }
    if (_sendCommand(
      'turn.interrupt',
      {},
      threadId: sessionId,
      turnId: turnId,
    )) {
      interactionNotice.value = '正在请求停止当前轮次…';
    }
  }

  void gitStatus({required bool includeDiff}) {
    // Protocol v1 exposes turn patches through thread.read, not a workspace
    // git-status command. Reconcile the selected timeline without clearing it.
    final threadId = selectedSessionId.value;
    if (threadId != null) _requestTimelineRead(threadId, force: true);
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
    _sendCommand('model.list', {'includeHidden': false, 'limit': 100});
    _sendCommand('host.get_status', {});
  }

  void startLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _catalogRefreshTimer?.cancel();
    // One catalog read paints the sidebar immediately. The fast loop below
    // only asks for compact status and relies on Relay events for content;
    // completed histories are reconciled on a much slower cadence.
    _refreshLiveTimeline(includeCatalog: true);
    _liveTimelineTimer = Timer.periodic(_liveTimelineInterval, (_) {
      _refreshLiveTimeline();
    });
    _catalogRefreshTimer = Timer.periodic(_catalogRefreshInterval, (_) {
      if (connected.value && !timelineRefreshing.value) {
        refreshProjects();
      }
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
    if (timelineRefreshing.value) return;
    final token = _beginTimelineRefresh(timeoutMessage: '项目刷新超时，请确认目标主机在线后重试。');
    if (!connected.value) {
      _finishTimelineRefresh(error: '项目刷新失败：当前 Relay 连接不可用，请重试。', token: token);
      return;
    }
    if (recoverEvents) {
      _requestEventRecovery();
    }
    final sent = _sendCommand(
      'thread.list',
      {'limit': 100},
      force: true,
      refreshToken: token,
    );
    _sendCommand('project.list', {'limit': 100}, refreshToken: token);
    if (!sent) {
      _finishTimelineRefresh(error: '项目刷新失败：当前 Relay 连接不可用，请重试。', token: token);
    }
  }

  void stopLiveTimelineRefresh() {
    _liveTimelineTimer?.cancel();
    _liveTimelineTimer = null;
    _catalogRefreshTimer?.cancel();
    _catalogRefreshTimer = null;
  }

  SessionCacheScope? _buildSessionCacheScope() {
    final pairing = activePairing;
    final pairingId = pairing?.id.trim() ?? activePairingId.value?.trim() ?? '';
    final space = spaceId.value.trim();
    final endpoint = deviceId.value.trim();
    final target = targetDeviceId.value.trim();
    if (pairingId.isEmpty ||
        space.isEmpty ||
        endpoint.isEmpty ||
        target.isEmpty) {
      return null;
    }
    final parts = [pairingId, space, endpoint, target];
    final key = parts.map(Uri.encodeComponent).join('\u001f');
    return SessionCacheScope(
      key: key,
      pairingId: pairingId,
      spaceId: space,
      endpointId: endpoint,
      targetDeviceId: target,
    );
  }

  String _timelineCacheKey(String threadId, {SessionCacheScope? scope}) {
    final activeScope = scope ?? _cacheScope;
    if (activeScope == null) return threadId.trim();
    return '${activeScope.key}\u0000${threadId.trim()}';
  }

  /// Usage reads never select another task or disturb the live transcript.
  Future<List<AnswerUsageRecord>> loadUsageStatistics() async {
    final scope = _buildSessionCacheScope();
    final selected = selectedSessionId.value ?? currentSessionId.value;
    final catalog = {for (final session in sessions) session.id: session};
    final current = selected == null
        ? <AnswerUsageRecord>[]
        : collectAnswerUsage(
            selected,
            events.toList(),
            session: catalog[selected],
          );
    if (scope == null) return current;
    await _flushCacheWrites();
    final stored = await _sessionCache.loadUsage(scope);
    if (_buildSessionCacheScope()?.key != scope.key) return [];
    final merged = {for (final record in stored) record.key: record};
    for (final record in current) {
      merged[record.key] = merged[record.key]?.merge(record) ?? record;
    }
    return merged.values.map((record) {
      final session = catalog[record.threadId];
      return session == null
          ? record
          : record.merge(
              AnswerUsageRecord(
                threadId: record.threadId,
                turnId: record.turnId,
                title: session.displayTitle,
                workspace: session.workspace,
              ),
            );
    }).toList();
  }

  Future<void> _activateSessionCache() async {
    final scope = _buildSessionCacheScope();
    if (scope == null) {
      // Invalidate any load that belongs to a pairing which has just been
      // cleared or is still being replaced.  Do this only for the no-scope
      // transition; incrementing the generation for an already-active scope
      // would invalidate the in-flight operation that callers are meant to
      // share below.
      _cacheGeneration += 1;
      _cacheScope = null;
      _cacheLoadedScopeKey = null;
      cacheHydrating.value = false;
      cacheStale.value = false;
      cacheLastUpdated.value = null;
      return;
    }
    if (_cacheScope?.key == scope.key) {
      final inFlight = _cacheLoadInFlight;
      if (inFlight != null) return inFlight;
      if (_cacheLoadedScopeKey == scope.key) return;
    }
    // A different scope (or a fresh load after the previous scope was
    // invalidated) gets a new generation.  Do not bump this before the
    // in-flight check above: connect/welcome can call activation twice in the
    // same frame, and the second call should await—not cancel—the first load.
    final generation = ++_cacheGeneration;
    _cacheScope = scope;
    cacheHydrating.value = true;
    cacheStale.value = true;
    final operation = () async {
      final snapshot = await _sessionCache.load(
        scope,
        timelineThreadId: _storedSessionId,
      );
      if (generation != _cacheGeneration || _cacheScope?.key != scope.key) {
        return;
      }
      _applyCachedSnapshot(scope, snapshot);
      // The catalog is intentionally loaded without every conversation
      // history. Hydrate only the task that was restored into the main view;
      // other timelines are fetched lazily when the user selects them.
      final selectedId = selectedSessionId.value?.trim() ?? '';
      if (selectedId.isNotEmpty) {
        await _loadCachedTimeline(selectedId);
      }
      if (generation != _cacheGeneration || _cacheScope?.key != scope.key) {
        return;
      }
      _cacheLoadedScopeKey = scope.key;
      cacheLastUpdated.value = snapshot.syncedAt;
      // Do not feed a persisted sequence back into sync.request. Connector
      // sequences are process-local and may have been reset after a restart;
      // the cached value is retained only as freshness metadata.
    }();
    _cacheLoadInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_cacheLoadInFlight, operation)) {
        _cacheLoadInFlight = null;
        if (generation == _cacheGeneration) cacheHydrating.value = false;
      }
    }
  }

  void _applyCachedSnapshot(
    SessionCacheScope scope,
    SessionCacheSnapshot snapshot,
  ) {
    if (snapshot.sessions.isNotEmpty) {
      final known = sessions.map((item) => item.id.trim()).toSet();
      final merged = List<SessionRecord>.of(sessions);
      for (final cached in snapshot.sessions) {
        if (known.add(cached.id.trim())) merged.add(cached);
      }
      merged.sort(compareSessionRecords);
      sessions.assignAll(merged.map(_sessionWithLiveStatus));
    }
    if (snapshot.workspaces.isNotEmpty) {
      final known = <String>{
        for (final workspace in workspaces)
          _normalizeWorkspaceKey(
            workspace.path.isNotEmpty ? workspace.path : workspace.name,
          ),
      };
      final merged = List<WorkspaceInfo>.of(workspaces);
      for (final cached in snapshot.workspaces) {
        final key = _normalizeWorkspaceKey(
          cached.path.isNotEmpty ? cached.path : cached.name,
        );
        if (key.isNotEmpty && known.add(key)) merged.add(cached);
      }
      if (merged.isNotEmpty) workspaces.assignAll(merged);
    }
    for (final entry in snapshot.eventsByThread.entries) {
      final key = _timelineCacheKey(entry.key, scope: scope);
      // A live event or an authoritative thread.read may have populated this
      // key while the disk snapshot was being decoded. Never let the older
      // snapshot roll that newer value back (an empty list is meaningful too).
      if (!_timelineMemoryCache.containsKey(key)) {
        _rememberTimelineMemory(key, entry.value);
      }
    }
    _deriveWorkspaces(sessions);
    selectedWorkspace.value ??= _restoreSelectedWorkspace();
    selectedWorkspace.value ??= _defaultWorkspace();
    _restoreLastSelectedSession(sessions.toList(growable: false));
    final selectedId = selectedSessionId.value?.trim();
    if (selectedId == null || selectedId.isEmpty || events.isNotEmpty) return;
    final cachedEvents = _readTimelineMemory(
      _timelineCacheKey(selectedId, scope: scope),
    );
    if (cachedEvents == null || cachedEvents.isEmpty) return;
    events.assignAll(cachedEvents);
    _bumpTimelineRevision();
    _finishTimelineLoad(sessionId: selectedId);
    SessionRecord? selected;
    for (final session in sessions) {
      if (session.id.trim() == selectedId) {
        selected = session;
        break;
      }
    }
    if (selected?.isRunning == true) {
      _setTimelineStatus(TimelineTaskStatus.processing);
    } else if (timelineStatus.value == TimelineTaskStatus.unknown ||
        timelineStatus.value == TimelineTaskStatus.loading) {
      _setTimelineStatus(TimelineTaskStatus.completed);
    }
  }

  Future<void> _loadCachedTimeline(String threadId) async {
    final id = threadId.trim();
    final scope = _cacheScope;
    if (id.isEmpty || scope == null) return;
    final key = _timelineCacheKey(id, scope: scope);
    final inMemory = _readTimelineMemory(key);
    if (inMemory != null && inMemory.isNotEmpty) {
      if (selectedSessionId.value?.trim() == id && events.isEmpty) {
        events.assignAll(_boundedInMemoryEvents(inMemory));
        _bumpTimelineRevision();
        _finishTimelineLoad(sessionId: id);
      }
      return;
    }
    final generation = _cacheGeneration;
    final loaded = await _sessionCache.loadTimeline(scope, id);
    if (generation != _cacheGeneration || _cacheScope?.key != scope.key) return;
    if (loaded.isEmpty) return;
    // A stream event or a newer thread.read can arrive while the disk query is
    // in flight. In that case the in-memory entry is already the fresher
    // source; do not overwrite it with the older query result.
    if (_timelineMemoryCache.containsKey(key)) {
      final current = _timelineMemoryCache[key]!;
      if (selectedSessionId.value?.trim() == id &&
          events.isEmpty &&
          current.isNotEmpty) {
        events.assignAll(_boundedInMemoryEvents(current));
        _bumpTimelineRevision();
        _finishTimelineLoad(sessionId: id);
      }
      return;
    }
    _rememberTimelineMemory(key, loaded);
    if (selectedSessionId.value?.trim() != id) return;
    final merged = _mergeLiveEvents(loaded);
    if (!_hasSameTimelineEvents(events, merged)) {
      events.assignAll(_boundedInMemoryEvents(merged));
      _bumpTimelineRevision();
    }
    _finishTimelineLoad(sessionId: id);
  }

  void _rememberVisibleTimeline() {
    final id = selectedSessionId.value?.trim();
    if (id == null || id.isEmpty || _cacheScope == null || events.isEmpty) {
      return;
    }
    _rememberTimelineMemory(_timelineCacheKey(id), events);
  }

  List<SessionEvent>? _readTimelineMemory(String key) {
    final value = _timelineMemoryCache[key];
    if (value == null) return null;
    _timelineMemoryCacheAccess[key] = ++_timelineMemoryCacheClock;
    return value;
  }

  void _rememberTimelineMemory(String key, List<SessionEvent> source) {
    final bounded = _boundedInMemoryEvents(source);
    _timelineMemoryCache.remove(key);
    _timelineMemoryCache[key] = bounded;
    _timelineMemoryCacheAccess[key] = ++_timelineMemoryCacheClock;
    while (_timelineMemoryCache.length > _maxInMemoryTimelineThreads) {
      String? oldestKey;
      var oldestAccess = 1 << 62;
      for (final entry in _timelineMemoryCacheAccess.entries) {
        if (entry.key == key) continue;
        if (entry.value < oldestAccess) {
          oldestKey = entry.key;
          oldestAccess = entry.value;
        }
      }
      if (oldestKey == null) break;
      _timelineMemoryCache.remove(oldestKey);
      _timelineMemoryCacheAccess.remove(oldestKey);
    }
  }

  List<SessionEvent> _boundedInMemoryEvents(List<SessionEvent> source) {
    if (source.isEmpty) return const <SessionEvent>[];
    final window = source.length <= _maxInMemoryTimelineEvents
        ? source
        : source.sublist(source.length - _maxInMemoryTimelineEvents);
    final firstUser = source.firstWhere(
      (event) => event.kind == 'user',
      orElse: () => window.first,
    );
    final selected = window.contains(firstUser)
        ? window
        : <SessionEvent>[
            firstUser,
            ...source.sublist(source.length - (_maxInMemoryTimelineEvents - 1)),
          ];
    return selected
        .map((event) {
          final text = event.text.length <= _maxInMemoryEventTextChars
              ? event.text
              : '${event.text.substring(0, _maxInMemoryEventTextChars)}\n…';
          var attachmentsChanged = false;
          final attachments = event.attachments
              .map((attachment) {
                // Keep the small preview/resource reference. An original
                // base64 payload is redundant once a thumbnail or signed
                // resource URL exists and is a common source of heap spikes.
                if (attachment.thumbnailDataUrl.trim().isNotEmpty ||
                    attachment.resourceUrl.trim().isNotEmpty ||
                    attachment.dataUrl.length > 2 * 1024 * 1024) {
                  if (attachment.dataUrl.isNotEmpty) attachmentsChanged = true;
                  return attachment.copyWith(dataUrl: '');
                }
                return attachment;
              })
              .toList(growable: false);
          if (text == event.text && !attachmentsChanged) {
            return event;
          }
          return event.copyWith(text: text, attachments: attachments);
        })
        .toList(growable: false);
  }

  void _trimVisibleTimeline() {
    var changed = false;
    final bounded = _boundedInMemoryEvents(events)
        .map((event) {
          if (event.text.length <= _maxInMemoryEventTextChars) return event;
          changed = true;
          return event.copyWith(
            text: '${event.text.substring(0, _maxInMemoryEventTextChars)}\n…',
          );
        })
        .toList(growable: false);
    if (changed || bounded.length != events.length) events.assignAll(bounded);
  }

  void _queueCatalogCacheWrite({DateTime? syncedAt}) {
    if (_cacheScope == null) return;
    _pendingCatalogCacheWrite = true;
    _pendingCacheSequence = _lastIncomingSequence;
    if (syncedAt != null) _pendingCacheSyncedAt = syncedAt;
    _scheduleCacheFlush();
  }

  /// Coalesces live stream changes into one current snapshot. The cache
  /// service diffs this snapshot against its row index and emits only changed
  /// rows/deletions to SQLite.
  void _queueTimelineCacheWrite(String? threadId) {
    final id = threadId?.trim();
    if (id == null || id.isEmpty || _cacheScope == null) return;
    final key = _timelineCacheKey(id);
    final snapshot = _boundedInMemoryEvents(events);
    _rememberTimelineMemory(key, snapshot);
    // If an authoritative replacement is already queued in this debounce
    // window, update its snapshot in place; it must include newer live events.
    _pendingTimelineCacheWrites[key] = snapshot;
    _scheduleCacheFlush();
  }

  /// Queues an authoritative timeline snapshot. This is used after
  /// `thread.read`, where stale rows must be removed as well as new rows
  /// written.
  void _queueTimelineCacheReplace(
    String? threadId, {
    List<SessionEvent>? snapshot,
  }) {
    final id = threadId?.trim();
    if (id == null || id.isEmpty || _cacheScope == null) return;
    final key = _timelineCacheKey(id);
    final next = _boundedInMemoryEvents(snapshot ?? events);
    _rememberTimelineMemory(key, next);
    _pendingTimelineCacheReplacements.add(key);
    _pendingTimelineCacheWrites[key] = next;
    _scheduleCacheFlush();
  }

  void _scheduleCacheFlush() {
    if (_cacheWriteTimer != null) return;
    _cacheWriteTimer = Timer(_cacheWriteDebounce, () {
      _cacheWriteTimer = null;
      unawaited(_flushCacheWrites());
    });
  }

  Future<void> _flushCacheWrites() {
    final inFlight = _cacheFlushInFlight;
    if (inFlight != null) {
      _cacheFlushRequested = true;
      return inFlight;
    }
    final operation = _drainCacheWrites();
    _cacheFlushInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_cacheFlushInFlight, operation)) {
        _cacheFlushInFlight = null;
      }
    });
  }

  Future<void> _drainCacheWrites() async {
    do {
      _cacheFlushRequested = false;
      await _flushCacheBatch();
    } while (_cacheFlushRequested || _hasPendingCacheWrites());
  }

  bool _hasPendingCacheWrites() {
    return _pendingCatalogCacheWrite || _pendingTimelineCacheWrites.isNotEmpty;
  }

  Future<void> _flushCacheBatch() async {
    final scope = _cacheScope;
    if (scope == null) {
      _pendingCatalogCacheWrite = false;
      _pendingTimelineCacheWrites.clear();
      _pendingTimelineCacheReplacements.clear();
      return;
    }
    final generation = _cacheGeneration;
    final writeCatalog = _pendingCatalogCacheWrite;
    final pendingSessions = _pendingCacheSequence;
    final pendingSyncedAt = _pendingCacheSyncedAt;
    final pendingTimelines = Map<String, List<SessionEvent>>.of(
      _pendingTimelineCacheWrites,
    );
    final pendingReplacements = Set<String>.of(
      _pendingTimelineCacheReplacements,
    );
    _pendingCatalogCacheWrite = false;
    _pendingCacheSequence = null;
    _pendingCacheSyncedAt = null;
    _pendingTimelineCacheWrites.clear();
    _pendingTimelineCacheReplacements.clear();
    if (writeCatalog) {
      if (generation != _cacheGeneration || _cacheScope?.key != scope.key) {
        return;
      }
      await _sessionCache.saveCatalog(
        scope,
        sessions: sessions.toList(growable: false),
        workspaces: workspaces.toList(growable: false),
        lastSequence: pendingSessions,
        syncedAt: pendingSyncedAt,
      );
      if (pendingSyncedAt != null && generation == _cacheGeneration) {
        cacheLastUpdated.value = pendingSyncedAt;
        cacheStale.value = false;
      }
    }
    for (final entry in pendingTimelines.entries) {
      if (generation != _cacheGeneration || _cacheScope?.key != scope.key) {
        return;
      }
      final separator = entry.key.indexOf('\u0000');
      final threadId = separator < 0
          ? entry.key
          : entry.key.substring(separator + 1);
      final session = sessions.firstWhereOrNull(
        (session) => session.id == threadId,
      );
      if (pendingReplacements.contains(entry.key)) {
        await _sessionCache.saveTimeline(
          scope,
          threadId,
          entry.value,
          session: session,
        );
      } else {
        await _sessionCache.saveTimelineIncremental(
          scope,
          threadId,
          entry.value,
          session: session,
        );
      }
    }
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
      final productMessage = RelayProtocol.unwrapProductMessage(decoded);
      if (productMessage == null) return;
      final productType = productMessage['type'] as String? ?? '';
      if (productType == 'codex.command.result') {
        _handleCommandResult(productMessage);
      } else if (productType == 'codex.event') {
        _consumeEvent(productMessage);
        final from = decoded['from'] as String? ?? targetDeviceId.value;
        if (from.isNotEmpty && _eventRecovery.sequence > 0) {
          _lastIncomingSequence = _eventRecovery.sequence;
          _sendRaw(
            RelayProtocol.ack(
              stream: decoded['streamId'] as String? ?? RelayProtocol.streamId,
              sequence: _lastIncomingSequence,
              targetDeviceId: from,
            ),
          );
        }
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
    // Relay snapshot revisions are scoped to the connector process. A fresh
    // connection may therefore start a new revision namespace; retain the
    // visible lifecycle but allow its first snapshot through.
    _timelineSnapshotGuard.resetRevision();
    connected.value = true;
    connectionLabel.value = 'online';
    if (_reconnectAttemptCount > 0) {
      _appendTransportTimelineEvent('连接已恢复');
    }
    _reconnectAttemptCount = 0;
    _hadOnlineConnection = true;
    _credentialRefreshBlocked = false;
    _tokenRefreshRetryAttempt = 0;
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
    _markUnconfirmedWrites();
    _pendingCommands.clear();
    _syncRecoveryInFlight = false;
    _scheduleTokenRefresh();
    cacheStale.value = true;
    unawaited(_activateSessionCache());
    unawaited(_storeConnectionHints());
    refreshProjects(recoverEvents: true);
    _sendCommand('model.list', {'includeHidden': false, 'limit': 100});
    _sendCommand('host.get_status', {});
  }

  void _handleRelayError(Map<String, dynamic> message) {
    final code = message['code'] as String? ?? 'relay.error';
    // A rejected optional resource/frame must not invalidate the authenticated
    // control channel. The Relay uses the same error envelope for these
    // request-level failures; keep task streaming alive and let the sender's
    // inline fallback handle the individual payload.
    if (code == 'resource.rejected' ||
        code == 'message.too_large' ||
        code == 'rate.limited' ||
        code == 'frame.invalid' ||
        code.startsWith('resource.')) {
      lastError.value = '部分资源未同步：${message['message'] ?? 'Relay 拒绝了可选数据'}';
      return;
    }
    final wasConnected = connected.value;
    _finishTimelineRefresh(
      error: '任务刷新失败：${message['message'] ?? 'Relay 返回错误'}',
    );
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
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
    cacheStale.value = true;
    final recoverableCredentialFailure =
        _isRefreshableRelayCode(code) && endpointGrant.value.isNotEmpty;
    if (wasConnected &&
        !recoverableCredentialFailure &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
    if (recoverableCredentialFailure) {
      // Both codes are recoverable when the proof-bound Grant is still
      // available. Keep every credential in storage and force the next
      // handshake to mint a fresh short-lived token.
      _forceTokenRefresh = true;
      _credentialRefreshBlocked = false;
      _beginCredentialRecoveryReconnect();
      return;
    }
    if (code.startsWith('auth.') || code == 'connection.revoked') {
      // Preserve the credentials so the user can inspect/rotate them from the
      // pairing page. Blindly clearing the Grant made an expired token
      // unrecoverable and caused an endless reconnect loop.
      _credentialRefreshBlocked = true;
      _forceTokenRefresh = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _tokenRefreshTimer?.cancel();
      _tokenRefreshTimer = null;
      unawaited(_closeSocket());
      unawaited(_storeConnectionHints());
      return;
    }
    _scheduleReconnect(reason: lastError.value);
  }

  /// Closes the expired-token socket before scheduling the replacement
  /// handshake.  Leaving the old socket alive while a reconnect timer is
  /// pending lets late frames race with the new connection and can also make
  /// Relay count two active sessions for the same endpoint.
  void _beginCredentialRecoveryReconnect() {
    if (_tokenRotationInProgress) return;
    final attempt = _connectionAttempt;
    final grant = endpointGrant.value;
    final relayUrl = baseUrl.value;
    final socket = _socket;
    _tokenRotationInProgress = true;
    connected.value = false;
    connectionLabel.value = 'reconnecting';
    unawaited(() async {
      try {
        await _closeSocketForRotation(socket);
      } catch (_) {
        // Closing an expired socket is best-effort; the reconnect attempt
        // below remains the source of truth for recovery.
      } finally {
        if (attempt == _connectionAttempt) {
          _tokenRotationInProgress = false;
        }
        if (attempt == _connectionAttempt &&
            !_manualDisconnect &&
            !_credentialRefreshBlocked &&
            endpointGrant.value == grant &&
            baseUrl.value == relayUrl) {
          // A credential rotation is an intentional lifecycle operation, so
          // it must finish even when the user disabled ordinary network
          // auto-reconnect in settings.
          _scheduleReconnect(force: true, reason: '连接凭证正在更新。');
        }
      }
    }());
  }

  void _handleCommandResult(Map<String, dynamic> message) {
    final requestId = message['requestId'] as String? ?? '';
    final pending = _pendingCommands.remove(requestId);
    if (pending == null) return;
    if (pending.kind == 'thread.settings.update' &&
        pending.settingsStreamId != _eventRecovery.streamId) {
      if (pending.completion?.isCompleted == false) {
        pending.completion!.complete(false);
      }
      return;
    }
    final success = message['success'] == true;
    if (pending.completion?.isCompleted == false) {
      pending.completion!.complete(success);
    }
    if (!success) {
      if (pending.kind == 'sync.request') _syncRecoveryInFlight = false;
      final error = message['error'];
      final errorMap = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      final text = errorMap['message'] as String? ?? '远程命令执行失败';
      if (pending.kind == 'project.list') {
        // Older App Servers do not expose project/list. Keep the task-derived
        // workspace fallback without surfacing an auxiliary capability error.
        return;
      }
      if (pending.interactionId != null) {
        submittedInteractions.remove(pending.interactionId);
        _reconcileSelectedTask();
      }
      if (pending.kind == 'thread.settings.update' &&
          pending.threadId != null) {
        _showThreadComposerSettings(pending.threadId!);
        _sendCommand(
          'thread.status',
          {},
          threadId: pending.threadId,
          force: true,
        );
      }
      if (errorMap['code'] == 'COMMAND_OUTCOME_UNKNOWN') {
        lastError.value = '命令结果尚未确认，正在核对任务；请勿重复发送。';
        if (pending.kind == 'thread.create') {
          _pendingSessionStart = false;
          _pendingPrompt = null;
        }
        _reconcileSelectedTask();
        _sendCommand('thread.list', {'limit': 100}, force: true);
        return;
      }
      if (pending.kind == 'turn.interrupt') interactionNotice.value = '';
      final isRefreshFailure = pending.refreshToken != null;
      if (isRefreshFailure) {
        _finishTimelineRefresh(
          error: '刷新失败：$text',
          token: pending.refreshToken,
        );
      }
      if (pending.kind == 'thread.read') {
        _failTimelineLoad('任务对话加载失败：$text');
      } else if (!isRefreshFailure) {
        lastError.value = '${errorMap['code'] ?? 'remote.error'}：$text';
      }
      final failedTurnStartBelongsToCurrent =
          pending.kind == 'turn.start' &&
          pending.threadId?.trim() == currentSessionId.value?.trim();
      if (failedTurnStartBelongsToCurrent) {
        // A rejected send does not mean the task itself failed. The desktop
        // may already be executing a competing turn; reconcile its real state.
        if (_currentTurnId == null) {
          _timelineSnapshotGuard.reset();
          _sessionLifecycles[pending.threadId]?.visibleRunning = false;
          _setTimelineStatus(TimelineTaskStatus.unknown);
        }
        _reconcileSelectedTask();
      } else if (pending.kind == 'thread.create') {
        _finishCurrentSession(
          status: TaskNotificationStatus.failed,
          sessionId: pending.threadId,
          message: text,
        );
      }
      return;
    }
    if (pending.refreshToken != null) {
      // The list and read requests are issued together. Either authoritative
      // response is enough to confirm that the manual refresh reached the
      // host; the normal timeline/event flow continues independently.
      _finishTimelineRefresh(token: pending.refreshToken);
    }
    if ((pending.kind == 'thread.list' || pending.kind == 'thread.read') &&
        _isTransientSyncError(lastError.value)) {
      lastError.value = '';
    }
    final result = message['result'];
    switch (pending.kind) {
      case 'sync.request':
        _applySyncResult(result);
      case 'thread.list':
        _applyThreadListResult(result);
      case 'project.list':
        _applyProjectListResult(result);
      case 'model.list':
        _applyModelListResult(result);
      case 'thread.create':
        _handleThreadCreated(result);
      case 'thread.read':
        _restoreInteractions(result, pending);
        _handleThreadReadResult(
          result,
          readGeneration: pending.timelineReadGeneration,
        );
      case 'thread.status':
        _restoreInteractions(result, pending);
        _handleThreadStatusResult(result, threadId: pending.threadId);
      case 'thread.settings.update':
        _applyThreadComposerSettings(pending.threadId, result);
      case 'turn.start':
        final startThreadId = pending.threadId?.trim();
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
        final interruptThreadId = pending.threadId?.trim();
        final interruptTurnId = pending.turnId?.trim();
        final currentThreadId = currentSessionId.value?.trim();
        final activeTurnId = _currentTurnId?.trim();
        if (interruptThreadId == null ||
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
        interactionNotice.value = '停止请求已提交，等待任务确认结束…';
        _reconcileSelectedTask();
      case 'approval.respond':
      case 'userInput.respond':
        _reconcileSelectedTask();
      case 'host.get_status':
        _applyHostStatus(result);
      default:
        break;
    }
  }

  void _requestEventRecovery() {
    if (_syncRecoveryInFlight) return;
    _syncRecoveryInFlight = true;
    if (!_sendCommand('sync.request', _eventRecovery.request, force: true)) {
      _syncRecoveryInFlight = false;
    }
  }

  bool _adoptEventStream(Object? rawId, {bool recover = true}) {
    final id = _readString(rawId);
    if (_eventRecovery.isRetired(id)) return false;
    if (_eventRecovery.adopt(id)) {
      _lastIncomingSequence = 0;
      _threadComposerSettings.clear();
      _timelineSnapshotGuard.resetRevision();
      _timelineSnapshotHash = null;
      _timelineReadGeneration++;
      _interactionRevision++;
      pendingInteractions.clear();
      submittedInteractions.clear();
      _pendingCommands.removeWhere(
        (_, pending) =>
            pending.kind == 'thread.read' ||
            pending.kind == 'thread.status' ||
            pending.kind == 'sync.request',
      );
      _syncRecoveryInFlight = false;
      cacheStale.value = true;
      if (recover) _requestEventRecovery();
    }
    return true;
  }

  void _consumeEvent(Map<String, dynamic> frame) {
    if (!_adoptEventStream(frame['eventStreamId'])) return;
    final value = frame['sequence'];
    if (value is num && value.isFinite) {
      final next = value.toInt();
      if (next <= _eventRecovery.sequence) return;
      if (!_eventRecovery.accept(next)) {
        _requestEventRecovery();
        return;
      }
    }
    _handleCodexEvent(frame);
  }

  void _applySyncResult(Object? value) {
    _syncRecoveryInFlight = false;
    final map = _asMap(value);
    if (map == null ||
        !_adoptEventStream(map['eventStreamId'], recover: false)) {
      return;
    }
    final mode = _readString(map['mode']);
    if (mode == 'events') {
      for (final item in _asList(map['events'])) {
        final frame = _asMap(item);
        if (frame != null) _consumeEvent(frame);
      }
      // Never advance past events we did not consume.
      final latest = map['latestSequence'];
      if (latest is num && latest > _eventRecovery.sequence) {
        _requestEventRecovery();
      }
      if (sessions.isEmpty || workspaces.isEmpty) {
        _sendCommand('thread.list', {'limit': 100});
        _sendCommand('project.list', {'limit': 100});
      }
    } else {
      if (map['eventStreamId'] == null) _eventRecovery.reset();
      final sequence = map['latestSequence'];
      if (sequence is num && sequence.isFinite && sequence >= 0) {
        _eventRecovery.snapshot(sequence.toInt());
      }
      _applyThreadListResult(map['threads']);
      if (map['projects'] != null) _applyProjectListResult(map['projects']);
      _applyHostStatus(map['status']);
      _reconcileSelectedTask();
      // Snapshot watermark was captured before its asynchronous reads. Replay
      // anything produced meanwhile, including the frame that exposed the gap.
      // Legacy hosts return snapshot again for an empty journal; do not loop.
      if (map['eventStreamId'] != null) _requestEventRecovery();
    }
    _lastIncomingSequence = _eventRecovery.sequence;
    _queueCatalogCacheWrite(syncedAt: DateTime.now().toUtc());
  }

  void _reconcileSelectedTask() {
    final id = selectedSessionId.value;
    if (id != null && id.isNotEmpty) _requestTimelineRead(id, force: true);
  }

  void _restoreInteractions(Object? value, _PendingCommand? pending) {
    final map = _asMap(value);
    if (map == null ||
        !map.containsKey('pendingInteractions') ||
        pending?.interactionRevision != _interactionRevision) {
      return;
    }
    final thread = _asMap(map['thread']);
    final id =
        _readString(thread?['id']) ??
        _readString(map['threadId']) ??
        pending?.threadId;
    if (id == null) return;
    pendingInteractions.removeWhere((_, item) => item.threadId == id);
    for (final raw in _asList(map['pendingInteractions'])) {
      final json = _asMap(raw);
      if (json == null) continue;
      final item = PendingInteraction.fromJson(json);
      if (item.id.isNotEmpty && item.threadId == id) {
        pendingInteractions[item.id] = item;
      }
    }
    submittedInteractions.removeWhere(
      (id) =>
          !pendingInteractions.containsKey(id) ||
          (!pendingInteractions[id]!.responding &&
              !_pendingCommands.values.any(
                (command) => command.interactionId == id,
              )),
    );
  }

  void respondToInteraction(
    PendingInteraction item,
    Map<String, dynamic> response,
  ) {
    if (!backendReady.value ||
        !item.canRespond ||
        item.responding ||
        submittedInteractions.contains(item.id) ||
        !pendingInteractions.containsKey(item.id)) {
      return;
    }
    final sent = _sendCommand(
      item.kind == 'userInput' ? 'userInput.respond' : 'approval.respond',
      {'approvalId': item.id, ...response},
      threadId: item.threadId,
      turnId: item.turnId,
      interactionId: item.id,
    );
    if (sent) {
      submittedInteractions.add(item.id);
    } else {
      lastError.value = '连接不可用，回答尚未发送。';
    }
  }

  Future<bool> steerCurrentTurn(String text) async {
    final threadId = selectedSessionId.value;
    final turnId = _currentTurnId;
    if (!backendReady.value ||
        !timelineStatus.value.isActive ||
        threadId == null ||
        turnId == null ||
        _pendingCommands.values.any(
          (pending) =>
              pending.kind == 'turn.steer' && pending.threadId == threadId,
        )) {
      lastError.value = '正在核对当前轮次，请稍后补充；草稿已保留。';
      _reconcileSelectedTask();
      return false;
    }
    final completion = Completer<bool>();
    if (!_sendCommand(
      'turn.steer',
      {'text': text},
      threadId: threadId,
      turnId: turnId,
      completion: completion,
    )) {
      lastError.value = '连接不可用，补充内容尚未发送。';
      return false;
    }
    return completion.future.timeout(
      _commandTimeout,
      onTimeout: () {
        lastError.value = '补充内容是否已送达尚未确认，请核对任务后再操作。';
        _reconcileSelectedTask();
        return false;
      },
    );
  }

  void _applyThreadListResult(Object? value) {
    final next = _dedupeSessions(
      _threadListItems(value)
          .map(_sessionFromThread)
          .whereType<SessionRecord>()
          .map(_preserveCatalogLifecycle),
    );
    _syncSessionCompletionNotifications(next);
    // App Server can briefly report an idle thread while its turn.started
    // event is already in flight. Keep the local running marker visible until
    // the matching terminal event arrives instead of making the sidebar
    // flicker back to a completed state on every catalog refresh.
    final reconciled = next.map(_sessionWithLiveStatus).toList()
      ..sort(compareSessionRecords);
    if (!_sameSessionList(sessions, reconciled)) {
      sessions.assignAll(reconciled);
    }
    _pruneSessionState();
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
    // Only a successful authoritative catalog response advances freshness.
    _queueCatalogCacheWrite(syncedAt: DateTime.now().toUtc());
  }

  bool _sameSessionList(List<SessionRecord> current, List<SessionRecord> next) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index += 1) {
      final left = current[index];
      final right = next[index];
      if (left.id != right.id ||
          left.workspace != right.workspace ||
          left.prompt != right.prompt ||
          left.status != right.status ||
          left.createdAt != right.createdAt ||
          left.updatedAt != right.updatedAt ||
          left.recencyAt != right.recencyAt ||
          left.projectId != right.projectId ||
          left.title != right.title ||
          left.isPinned != right.isPinned ||
          left.isArchived != right.isArchived) {
        return false;
      }
    }
    return true;
  }

  SessionRecord _preserveCatalogLifecycle(SessionRecord incoming) {
    final incomingStatus = _timelineStatusFromValue(incoming.status);
    if (incomingStatus != TimelineTaskStatus.unknown) return incoming;
    for (final previous in sessions) {
      if (previous.id.trim() != incoming.id.trim()) continue;
      final previousStatus = _timelineStatusFromValue(previous.status);
      if (previousStatus.isTerminal &&
          incomingStatus.isTerminal &&
          previousStatus != incomingStatus) {
        // Thread/list does not carry a turn id, so a terminal-to-terminal
        // change cannot prove that a newer turn exists. Keep the prior value
        // until thread/status or thread/read correlates the turn explicitly.
        return incoming.copyWith(status: previous.status);
      }
      // A catalog row with `notLoaded` only means that its history was not
      // hydrated. Keep the last known lifecycle until status/read reconciliation
      // provides positive evidence for a transition.
      if (previous.status.trim().isNotEmpty &&
          _timelineStatusFromValue(previous.status) !=
              TimelineTaskStatus.unknown) {
        return incoming.copyWith(status: previous.status);
      }
      break;
    }
    return incoming;
  }

  void _applyProjectListResult(Object? value) {
    final items = _projectListItems(value);
    final projects = items
        .map(_workspaceFromProject)
        .whereType<WorkspaceInfo>()
        .toList(growable: false);
    if (items.isEmpty) {
      _officialWorkspaces.clear();
      _deriveWorkspaces(sessions);
      _queueCatalogCacheWrite();
      return;
    }
    if (projects.isEmpty) return;
    _officialWorkspaces
      ..clear()
      ..addAll(projects);
    _deriveWorkspaces(sessions);
    selectedWorkspace.value ??= _restoreSelectedWorkspace();
    selectedWorkspace.value ??= _defaultWorkspace();
    _queueCatalogCacheWrite();
  }

  List<Object?> _projectListItems(Object? value) {
    var current = value;
    for (var depth = 0; depth < 3; depth += 1) {
      if (current is List) return List<Object?>.from(current);
      final map = _asMap(current);
      if (map == null) return const [];
      Object? next;
      for (final key in const [
        'data',
        'projects',
        'items',
        'results',
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

  WorkspaceInfo? _workspaceFromProject(Object? value) {
    final map = _asMap(value);
    if (map == null) return null;
    final project = _asMap(map['project']) ?? map;
    final roots = _asList(project['roots'])
        .map((root) {
          final rootMap = _asMap(root);
          return _readString(rootMap?['path']) ?? _readString(root);
        })
        .whereType<String>()
        .toList(growable: false);
    final name =
        _readString(project['name']) ??
        (roots.isEmpty ? '' : _lastPathSegment(roots.first));
    final path =
        _readString(project['path']) ?? (roots.isEmpty ? '' : roots.first);
    if (name.isEmpty && path.isEmpty) return null;
    return WorkspaceInfo(
      id: _readString(project['id']) ?? '',
      name: name,
      path: path,
      position: (project['position'] as num?)?.toInt(),
      roots: roots,
    );
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
    for (final session in records) {
      final id = session.id.trim();
      if (id.isEmpty) continue;
      final previous = byId[id];
      if (previous == null) {
        byId[id] = session;
      } else if (compareSessionRecords(session, previous) < 0) {
        byId[id] = session;
      }
    }
    return byId.values.toList()..sort(compareSessionRecords);
  }

  void _upsertSession(SessionRecord record) {
    final id = record.id.trim();
    if (id.isEmpty) return;
    record = _sessionWithLiveStatus(record);
    final index = sessions.indexWhere((item) => item.id.trim() == id);
    if (index >= 0) {
      sessions[index] = record;
    } else {
      sessions.add(record);
    }
    sessions.sort(compareSessionRecords);
    _pruneSessionState();
    _queueCatalogCacheWrite();
  }

  void _pruneSessionState() {
    final known = sessions
        .map((session) => session.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final selected = selectedSessionId.value?.trim();
    final current = currentSessionId.value?.trim();
    if (selected != null && selected.isNotEmpty) known.add(selected);
    if (current != null && current.isNotEmpty) known.add(current);
    _sessionLifecycles.removeWhere((id, _) => !known.contains(id));
    _notifiedTerminalSessions.removeWhere((id) => !known.contains(id));
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
    final workspace = _workspaceForSession(selected);
    if (workspace != null &&
        !_sameWorkspace(selectedWorkspace.value, workspace)) {
      selectedWorkspace.value = workspace;
      unawaited(_storeSelectedWorkspace(workspace));
    }
    selectedSessionId.value = selected.id;
    currentSessionId.value = selected.id;
    _timelineSnapshotGuard.reset();
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
    if (_officialWorkspaces.isNotEmpty) {
      final ordered = List<WorkspaceInfo>.of(_officialWorkspaces)
        ..sort((left, right) {
          final leftPosition = left.position ?? 1 << 30;
          final rightPosition = right.position ?? 1 << 30;
          final position = leftPosition.compareTo(rightPosition);
          if (position != 0) return position;
          return left.id.compareTo(right.id);
        });
      final knownPaths = <String>{};
      for (final workspace in ordered) {
        knownPaths.add(_normalizeWorkspaceKey(workspace.path));
        knownPaths.addAll(
          workspace.roots
              .map(_normalizeWorkspaceKey)
              .where((path) => path.isNotEmpty),
        );
      }
      final extras = <String, DateTime>{};
      for (final record in records) {
        final path = _normalizeWorkspaceKey(record.workspace);
        if (path.isEmpty || knownPaths.contains(path)) continue;
        final previous = extras[path];
        if (previous == null || record.recencyAtDate.isAfter(previous)) {
          extras[path] = record.recencyAtDate;
        }
      }
      final extraPaths = extras.keys.toList()
        ..sort((left, right) {
          final activity = extras[right]!.compareTo(extras[left]!);
          if (activity != 0) return activity;
          return left.compareTo(right);
        });
      workspaces.assignAll([
        ...ordered,
        ...extraPaths.map(
          (path) => WorkspaceInfo(name: _lastPathSegment(path), path: path),
        ),
      ]);
      return;
    }
    final byPath = <String, WorkspaceInfo>{};
    final latestByPath = <String, DateTime>{};
    for (final record in records) {
      final path = record.workspace.trim();
      if (path.isEmpty) continue;
      byPath[path] = WorkspaceInfo(name: _lastPathSegment(path), path: path);
      final latest = record.recencyAtDate;
      final previous = latestByPath[path];
      if (previous == null || latest.isAfter(previous)) {
        latestByPath[path] = latest;
      }
    }
    if (byPath.isNotEmpty) {
      final orderedPaths = byPath.keys.toList()
        ..sort((left, right) {
          final activity = latestByPath[right]!.compareTo(latestByPath[left]!);
          if (activity != 0) return activity;
          return left.compareTo(right);
        });
      workspaces.assignAll(
        orderedPaths.map((path) => byPath[path]!).toList(growable: false),
      );
    }
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
    final recency = _dateString(thread['recencyAt'] ?? thread['recency_at']);
    final projectId =
        _readString(thread['projectId'] ?? thread['project_id']) ?? '';
    return SessionRecord(
      id: id,
      workspace: workspace,
      prompt: prompt,
      status: status,
      createdAt: created,
      updatedAt: updated.isEmpty ? created : updated,
      recencyAt: recency,
      projectId: projectId,
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
    final rawStatus = status is Map
        ? (_readString(status['type']) ??
              _readString(status['state']) ??
              _readString(status['status']))
        : _readString(status);
    final normalizedStatus = rawStatus == null
        ? null
        : _normalizeThreadStatus(rawStatus);
    final flags = _threadActiveFlags(thread);
    if (_hasActiveThreadFlag(flags)) return 'running';
    final currentTurn =
        _asMap(thread['turn']) ??
        _asMap(thread['currentTurn']) ??
        _asMap(thread['current_turn']);
    if (currentTurn != null) {
      final turnStatus = _timelineStatusFromTurn(currentTurn);
      if (turnStatus.isActive) return 'running';
      // `notLoaded` describes the thread history payload, not the lifecycle
      // of a turn that is present in the same snapshot.  When a turn carries
      // an explicit terminal status/timestamp, prefer that evidence so a
      // completed task does not remain stuck in the loading state.
      if (turnStatus.isTerminal) {
        return _sessionStatusForTimeline(turnStatus);
      }
    }
    final turns = _asList(thread['turns']);
    if (turns.isNotEmpty) {
      final latestTurn = _latestTurnFromSnapshot(turns);
      if (latestTurn != null) {
        final turnStatus = _timelineStatusFromTurn(latestTurn);
        if (turnStatus.isActive) return 'running';
        if (turnStatus.isTerminal) {
          return _sessionStatusForTimeline(turnStatus);
        }
      }
    }
    // A catalog snapshot without lifecycle evidence is not proof that the
    // task completed.  In particular, a desktop-owned active thread can be
    // visible here before its persisted status catches up.  Keep it in an
    // explicit synchronizing state so the sidebar never fabricates a terminal
    // status from missing metadata.
    return normalizedStatus?.isNotEmpty == true ? normalizedStatus! : 'unknown';
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
      // `notLoaded` only describes the history payload, not the lifecycle.
      // Treating it as done is what made a still-running task look terminal
      // after a catalog refresh.
      'idle' => 'done',
      'notloaded' => 'unknown',
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
    String? turnId,
  }) {
    timelineStatus.value = status;
    if (status.isActive || status.isTerminal) {
      _timelineSnapshotGuard.recordTrusted(status, turnId: turnId);
    }
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

  bool _hasActiveThreadFlag(Iterable<String> flags) {
    for (final raw in flags) {
      final flag = raw.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
      if (flag == 'waitingonapproval' ||
          flag == 'waiting_on_approval' ||
          flag == 'waitingonuserinput' ||
          flag == 'waiting_on_user_input' ||
          flag == 'active' ||
          flag == 'running' ||
          flag == 'processing' ||
          flag == 'inprogress' ||
          flag == 'in_progress' ||
          flag == 'executing' ||
          flag == 'working') {
        return true;
      }
    }
    return false;
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
    if (_hasActiveThreadFlag(flags)) {
      if (flags.contains('waitingonapproval') ||
          flags.contains('waiting_on_approval')) {
        return TimelineTaskStatus.waitingApproval;
      }
      if (flags.contains('waitingonuserinput') ||
          flags.contains('waiting_on_user_input')) {
        return TimelineTaskStatus.waitingUserInput;
      }
      return TimelineTaskStatus.processing;
    }
    if (flags.contains('waitingonapproval') ||
        flags.contains('waiting_on_approval')) {
      return TimelineTaskStatus.waitingApproval;
    }
    if (flags.contains('waitingonuserinput') ||
        flags.contains('waiting_on_user_input')) {
      return TimelineTaskStatus.waitingUserInput;
    }
    final status = thread['status'];
    final rawStatus = status is Map
        ? (_readString(status['type']) ??
              _readString(status['state']) ??
              _readString(status['status']))
        : _readString(status);
    final parsedStatus = _timelineStatusFromValue(rawStatus);
    final statusIsNotLoaded =
        rawStatus?.trim().toLowerCase().replaceAll('_', '') == 'notloaded';
    // Older snapshots may expose only a current turn object.  It is still a
    // valid lifecycle source and, importantly, understands `inProgress`.
    final currentTurn =
        _asMap(thread['turn']) ??
        _asMap(thread['currentTurn']) ??
        _asMap(thread['current_turn']);
    if (currentTurn != null) {
      final turnStatus = _timelineStatusFromTurn(currentTurn);
      // A current in-progress turn outranks a stale thread-level idle or
      // interrupted value while the server is still catching up.
      // A terminal turn is also authoritative when the thread-level status is
      // `notLoaded`: that value only says that history metadata was not loaded
      // by the server, not that the turn is still running.
      if (turnStatus.isActive ||
          turnStatus.isTerminal ||
          (!statusIsNotLoaded && parsedStatus == TimelineTaskStatus.unknown)) {
        return turnStatus;
      }
    }
    final turns = _asList(thread['turns']);
    if (turns.isNotEmpty) {
      final latestTurn = _latestTurnFromSnapshot(turns);
      if (latestTurn != null) {
        final turnStatus = _timelineStatusFromTurn(latestTurn);
        if (turnStatus.isActive ||
            turnStatus.isTerminal ||
            (!statusIsNotLoaded &&
                parsedStatus == TimelineTaskStatus.unknown)) {
          return turnStatus;
        }
      }
    }
    return parsedStatus;
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

  TimelineTaskStatus _terminalStatusFromTurnEvent(
    String type,
    Map<String, dynamic> turn,
  ) {
    final declared = _timelineStatusFromTurn(turn);
    if (declared.isActive) return declared;
    if (declared.isTerminal) return declared;
    // The current App Server uses turn/completed for every terminal turn and
    // carries the precise outcome in turn.status. If that field is omitted,
    // the method name is the only reliable terminal evidence available.
    return type == 'turn.completed'
        ? TimelineTaskStatus.completed
        : TimelineTaskStatus.unknown;
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

    final selectedId = selectedSessionId.value?.trim();

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
              recencyAt: parsed?.recencyAt.trim().isNotEmpty == true
                  ? parsed!.recencyAt
                  : base.recencyAt,
              projectId: parsed?.projectId.trim().isNotEmpty == true
                  ? parsed!.projectId
                  : base.projectId,
              title: parsed?.title.trim().isNotEmpty == true
                  ? parsed!.title
                  : base.title,
              isPinned: parsed?.isPinned == true || base.isPinned,
              isArchived: parsed?.isArchived == true || base.isArchived,
            );
      _upsertSession(merged);
      _deriveWorkspaces(sessions);
    }

    if (selectedId != id.trim()) return;
    // Queue/status updates can arrive without a complete Thread status. They
    // still mean that the selected thread may have a new user turn or newly
    // persisted output, so hydrate it immediately instead of waiting for the
    // periodic poll to notice the change.
    if (status == TimelineTaskStatus.unknown) {
      _requestTimelineRead(id, force: true);
      return;
    }
    final wasActive = timelineStatus.value.isActive;
    DateTime? statusStartedAt;
    if (status.isActive) {
      currentSessionId.value = id;
      final turn = _asMap(thread['currentTurn']) ?? _asMap(thread['turn']);
      final observedStartedAt = turn == null
          ? null
          : _turnTimestamp(turn, 'startedAt');
      if (observedStartedAt != null &&
          (turnId == null || _turnIdFromTurn(turn!) == turnId)) {
        _currentTurnStartedAt = observedStartedAt;
      } else if (timelineStatus.value.isTerminal ||
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
        _timelineSnapshotGuard.clearTurnIdentity();
      }
      _markSessionRunningForNotification(id);
    }
    _setTimelineStatus(
      status,
      startedAt: statusStartedAt,
      activeFlags: _threadActiveFlags(thread),
      turnId: status.isActive ? turnId : _lastTerminalTurnId,
    );
    if (status.isActive && (events.isEmpty || events.last.kind != 'running')) {
      _appendSessionEvent(SessionEvent(kind: 'running', text: status.label));
    }
    if (status.isActive) {
      _requestTimelineRead(id, force: !wasActive);
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
    final draftContext = composerContext.value;
    final draftPermission = permissionMode.value;
    _pendingSessionStart = false;
    currentSessionId.value = record.id;
    selectedSessionId.value = record.id;
    _applyThreadComposerSettings(record.id, value);
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
      if (_sendComposerSettings({
        if (draftContext.model.isNotEmpty) 'model': draftContext.model,
        if (draftContext.reasoningEffort.isNotEmpty)
          'effort': draftContext.reasoningEffort,
        'permissionMode': draftPermission,
      }, threadId: record.id)) {
        _sendTurnStart(prompt, threadId: record.id);
      }
    }
  }

  /// Applies the metadata-only status heartbeat for the selected task. This
  /// is deliberately separate from thread.read: a status response is small
  /// enough to poll even for completed threads, while a full read is only
  /// requested once the heartbeat proves that a turn is active (or when the
  /// selected task still needs hydration).
  void _handleThreadStatusResult(Object? value, {String? threadId}) {
    final map = _asMap(value);
    _applyThreadComposerSettings(threadId, map);
    final thread = _asMap(map?['thread']) ?? map;
    if (thread == null) return;
    final id =
        _readString(thread['id']) ??
        _readString(thread['threadId']) ??
        _readString(thread['thread_id']) ??
        threadId?.trim();
    if (id == null || id.isEmpty) return;

    final status = _timelineStatusFromThread(thread);
    final selectedId = selectedSessionId.value?.trim();
    if (status == TimelineTaskStatus.unknown) {
      if (selectedId == id) {
        // `notLoaded` describes an incomplete snapshot, not a lifecycle
        // transition. Keep the last trusted active/terminal status visible;
        // the read below will update it once persisted data catches up.
        _timelineSnapshotGuard.acceptSnapshot(
          TimelineTaskStatus.unknown,
          revision: _snapshotRevisionFromValue(value),
        );
        _requestTimelineRead(id);
      }
      return;
    }

    final currentTurn =
        _asMap(thread['turn']) ??
        _asMap(thread['currentTurn']) ??
        _asMap(thread['current_turn']);
    final currentTurnStatus = currentTurn == null
        ? TimelineTaskStatus.unknown
        : _timelineStatusFromTurn(currentTurn);
    final statusTurnId = currentTurn == null
        ? null
        : _turnIdFromTurn(currentTurn);
    final lifecycle = _sessionLifecycles[id];
    final localRunning =
        lifecycle?.visibleRunning == true ||
        (selectedId == id && timelineStatus.value.isActive);
    final statusTurnMatchesCurrent =
        currentTurnStatus.isTerminal &&
        statusTurnId != null &&
        statusTurnId.isNotEmpty &&
        _currentTurnId != null &&
        statusTurnId == _currentTurnId;
    if (status.isTerminal && localRunning && !statusTurnMatchesCurrent) {
      // Thread status is a snapshot without a turn id. A stale idle or
      // interrupted snapshot must not terminate a locally active turn. Wait
      // for the matching turn event or a read that carries terminal turn
      // evidence instead of projecting an ambiguous status into the UI. The
      // read is requested here as well because the status event may be the
      // only signal that a desktop turn started while the phone was quiet.
      _requestTimelineRead(id);
      return;
    }

    // A status-only response can omit metadata on older servers. Preserve the
    // existing sidebar row and update only its lifecycle value in that case.
    if (selectedId != id) {
      _applySessionStatusValue(id, status, value);
      return;
    }

    if (status.isActive) {
      if (!_timelineSnapshotGuard.acceptSnapshot(
        status,
        turnId: statusTurnId,
        revision: _snapshotRevisionFromValue(value),
      )) {
        return;
      }
      _applySessionStatusValue(id, status, value);
      final wasActive = timelineStatus.value.isActive;
      if (timelineStatus.value.isTerminal &&
          (statusTurnId == null || statusTurnId.isEmpty)) {
        // A new turn can be reported as active before its id is persisted.
        // Forget the previous terminal turn id so its delayed interrupted
        // notification cannot terminate this new turn.
        _currentTurnId = null;
        _timelineSnapshotGuard.clearTurnIdentity();
      }
      if (statusTurnId != null &&
          statusTurnId.isNotEmpty &&
          (!wasActive ||
              _currentTurnId == null ||
              _currentTurnId == statusTurnId)) {
        _currentTurnId = statusTurnId;
        _lastTerminalTurnId = null;
      }
      final trackedTurnId = _currentTurnId == statusTurnId
          ? statusTurnId
          : _currentTurnId;
      currentSessionId.value = id;
      _markSessionRunningForNotification(id);
      final startedAt =
          (currentTurn != null && trackedTurnId == statusTurnId
              ? _turnTimestamp(currentTurn, 'startedAt')
              : null) ??
          _currentTurnStartedAt ??
          timelineTurnStartedAt.value ??
          DateTime.now();
      _currentTurnStartedAt = startedAt;
      _setTimelineStatus(
        status,
        startedAt: startedAt,
        activeFlags: _threadActiveFlags(thread),
        turnId: trackedTurnId,
      );
      if (_requestedEventsSessionId != id) {
        _requestedEventsSessionId = id;
        for (final session in sessions) {
          if (session.id.trim() == id) {
            _requestedEventsPrompt = session.prompt;
            break;
          }
        }
      }
      // Do not force this read: an in-flight hydration/read response is still
      // useful and the command coalescer will keep only one request per task.
      _requestTimelineRead(id, force: !wasActive);
      if (events.isEmpty || events.last.kind != 'running') {
        _appendSessionEvent(SessionEvent(kind: 'running', text: status.label));
      }
      return;
    }

    if (_shouldIgnoreTerminalLifecycle(
      threadId: id,
      turnId: statusTurnId,
      status: status,
    )) {
      return;
    }

    if (!_timelineSnapshotGuard.acceptSnapshot(
      status,
      turnId: statusTurnId,
      revision: _snapshotRevisionFromValue(value),
    )) {
      return;
    }
    _applySessionStatusValue(id, status, value);

    // A terminal status is accepted only after the current turn identity has
    // been correlated above. The following read then hydrates the final
    // answer and duration without allowing an older turn to overwrite it.
    final previousStatus = timelineStatus.value;
    final statusChanged = previousStatus != status;
    final wasLocallyRunning =
        previousStatus.isActive || lifecycle?.visibleRunning == true;
    final terminalTurnId = statusTurnId;
    _markSessionTerminal(id);
    _setTimelineStatus(
      status,
      activeFlags: _threadActiveFlags(thread),
      turnId: terminalTurnId,
    );
    if (terminalTurnId != null && terminalTurnId.isNotEmpty) {
      _currentTurnId = terminalTurnId;
      _lastTerminalTurnId = terminalTurnId;
    }
    if (currentSessionId.value?.trim() == id) {
      currentSessionId.value = null;
    }
    if (wasLocallyRunning) {
      SessionRecord? session;
      for (final candidate in sessions) {
        if (candidate.id.trim() == id) {
          session = candidate;
          break;
        }
      }
      unawaited(
        _notifySessionFinishedOnce(
          status: _notificationStatusForTimeline(status),
          sessionId: id,
          notificationKey: session == null
              ? id
              : _notificationKeyForSession(session),
          workspaceName: session == null
              ? null
              : _workspaceNameForSession(session.workspace),
          prompt: session?.prompt,
        ),
      );
    }
    if (statusChanged || _requestedEventsSessionId != id || events.isEmpty) {
      _requestedEventsSessionId = id;
      _beginTimelineLoad(id);
      _sendCommand('thread.read', {}, threadId: id);
    }
  }

  void _applySessionStatusValue(
    String id,
    TimelineTaskStatus status,
    Object? value,
  ) {
    final sessionIndex = sessions.indexWhere(
      (session) => session.id.trim() == id,
    );
    final sessionStatus = _sessionStatusForTimeline(status);
    if (sessionIndex >= 0) {
      final previous = sessions[sessionIndex];
      final previousStatus = _timelineStatusFromValue(previous.status);
      if (previousStatus.isTerminal &&
          status.isTerminal &&
          previousStatus != status) {
        return;
      }
      if (previousStatus.isActive &&
          status.isTerminal &&
          _sessionLifecycles[id]?.visibleRunning == true) {
        return;
      }
      if (previous.status != sessionStatus) {
        sessions[sessionIndex] = previous.copyWith(status: sessionStatus);
        _queueCatalogCacheWrite();
      }
    } else {
      final parsed = _sessionFromThread(value);
      if (parsed != null) _upsertSession(parsed);
    }
  }

  /// Hydrates the selected thread after an event-driven lifecycle change.
  ///
  /// Streaming deltas update the transcript directly, but Codex does not
  /// emit a user-message delta when a prompt arrives from another client.
  /// Status/queue notifications are therefore the trigger for a read that
  /// discovers that prompt and any output persisted since the last snapshot.
  /// The command coalescer keeps this safe when a periodic heartbeat is
  /// already reading the same thread.
  bool _requestTimelineRead(String sessionId, {bool force = false}) {
    final id = sessionId.trim();
    if (id.isEmpty || !connected.value) return false;
    if (_requestedEventsSessionId != id) {
      _requestedEventsSessionId = id;
      for (final session in sessions) {
        if (session.id.trim() == id) {
          _requestedEventsPrompt = session.prompt;
          break;
        }
      }
    }
    if (force || (events.isEmpty && !timelineLoading.value)) {
      _beginTimelineLoad(id);
    }
    return _sendCommand('thread.read', {}, threadId: id, force: force);
  }

  String _sessionStatusForTimeline(TimelineTaskStatus status) {
    return switch (status) {
      TimelineTaskStatus.processing ||
      TimelineTaskStatus.waitingApproval ||
      TimelineTaskStatus.waitingUserInput => 'running',
      TimelineTaskStatus.failed => 'error',
      TimelineTaskStatus.interrupted => 'interrupted',
      TimelineTaskStatus.completed => 'completed',
      _ => 'unknown',
    };
  }

  TaskNotificationStatus _notificationStatusForTimeline(
    TimelineTaskStatus status,
  ) {
    return switch (status) {
      TimelineTaskStatus.failed => TaskNotificationStatus.failed,
      TimelineTaskStatus.interrupted => TaskNotificationStatus.interrupted,
      _ => TaskNotificationStatus.completed,
    };
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
    _applyThreadComposerSettings(_readString(map?['threadId']), map);
    if (map?['unchanged'] == true) {
      // This is an acknowledgement, never an empty transcript or a terminal
      // lifecycle update. Keep deltas that arrived after the last snapshot.
      if (map?['threadId'] == _requestedEventsSessionId &&
          map?['threadId'] == _timelineSnapshotHashSessionId &&
          map?['snapshotHash'] == _timelineSnapshotHash) {
        _finishTimelineLoad(sessionId: _requestedEventsSessionId);
      }
      return;
    }
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
    _applyThreadComposerSettings(sessionId, value);
    _timelineSnapshotHash = _readString(map?['snapshotHash']);
    _timelineSnapshotHashSessionId = sessionId;
    _timelineSnapshotHashReceivedAt = DateTime.now();
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
    final latestActiveTurnIsStale =
        localStatusIsActive &&
        latestTurnStatus.isActive &&
        latestTurnId != null &&
        _currentTurnId != null &&
        latestTurnId != _currentTurnId;
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
        : latestTurnStatus.isActive && !latestActiveTurnIsStale
        ? latestTurnStatus
        : latestTerminalIsStale || localActiveShouldWin
        ? localActiveStatus
        : latestTurnStatus != TimelineTaskStatus.unknown
        ? latestTurnStatus
        : threadSnapshotStatus;
    final snapshotTurnIdForGuard =
        localStatusIsActive &&
            snapshotStatus.isActive &&
            (latestActiveTurnIsStale ||
                (!latestTurnStatus.isActive && !latestTurnMatchesCurrent))
        ? _currentTurnId
        : latestTurnId;
    final snapshotAccepted = _timelineSnapshotGuard.acceptSnapshot(
      snapshotStatus,
      turnId: snapshotTurnIdForGuard,
      revision: _snapshotRevisionFromValue(value),
    );
    if (!snapshotAccepted) {
      // A stale/ambiguous snapshot may still contain useful transcript items,
      // so continue below to merge content, but do not mutate lifecycle state.
    }
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
    if (snapshotAccepted && snapshotStatus != TimelineTaskStatus.unknown) {
      _setTimelineStatus(
        snapshotStatus,
        startedAt: resolvedStartedAt,
        activeFlags: _threadActiveFlags(thread),
        turnId: snapshotTurnIdForGuard,
      );
      if (snapshotStatus.isActive) {
        currentSessionId.value = sessionId;
        _currentTurnStartedAt = resolvedStartedAt;
        // `thread.read` is authoritative only for the turn it describes.
        // In particular, do not replace a locally tracked active turn with a
        // terminal id from an older paginated snapshot.
        if (latestTurnId != null &&
            !staleTerminalTurnInActiveSnapshot &&
            !latestActiveTurnIsStale) {
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
    } else if (snapshotStatus == TimelineTaskStatus.unknown) {
      // A valid snapshot without lifecycle fields is not proof of a
      // transition. Preserve the last trusted status instead of oscillating
      // between "状态同步中…" and an old terminal turn.
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
            turnId: snapshotTurnId,
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

      // Preserve per-turn metadata even when history has no token usage on
      // individual items. The identity matches live terminal notifications.
      final turnUsage = readTokenUsage(turnMap, scope: TokenUsageScope.turn);
      final contextUsage = readContextWindowUsage(turnMap);
      final hasExplicitTerminal =
          turnStatus.isTerminal ||
          (turnStatus == TimelineTaskStatus.unknown &&
              (turnDurationMs != null || turnCompletedAt != null));
      if (hasExplicitTerminal) {
        final resolvedDuration =
            turnDurationMs ?? _durationBetween(turnStartedAt, turnCompletedAt);
        final resolvedEnd =
            turnCompletedAt ??
            (turnStartedAt != null && resolvedDuration != null
                ? turnStartedAt.add(Duration(milliseconds: resolvedDuration))
                : null);
        loaded.add(
          SessionEvent(
            kind: 'done',
            text: '',
            time: resolvedEnd,
            completedAt: resolvedEnd,
            durationMs: resolvedDuration,
            usage: turnUsage,
            contextWindowUsage: contextUsage,
            turnId: snapshotTurnId,
            itemId: snapshotTurnId == null ? null : 'turn-end:$snapshotTurnId',
          ),
        );
      } else if ((turnUsage != null || contextUsage != null) &&
          snapshotTurnId != null) {
        loaded.add(
          SessionEvent(
            kind: 'token_usage',
            text: '',
            usage: turnUsage,
            contextWindowUsage: contextUsage,
            turnId: snapshotTurnId,
            itemId:
                'turn-usage:$snapshotTurnId:${turnUsage?.scope.name ?? 'context'}',
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
          turnId: _currentTurnId,
        ),
      );
    }
    _refreshGitSnapshotFromEvents(loaded);

    // An empty thread is a valid response (for example, a newly-created
    // task that has not produced output yet). It must still end the loading
    // state so the user gets an actionable empty state instead of a spinner
    // that never resolves.
    _finishTimelineLoad(sessionId: requestedSessionId);
    // The read can race a live event. An empty (or user-only) snapshot is not
    // permission to erase deltas already rendered in memory; merge first and
    // persist the merged value so a debounced cache write cannot resurrect an
    // empty history on the next reload.
    final merged = _mergeLiveEvents(loaded);
    if (!_hasSameTimelineEvents(events, merged)) {
      events.assignAll(_boundedInMemoryEvents(merged));
      _bumpTimelineRevision();
    }
    _refreshGitSnapshotFromEvents(events);
    _rememberTimelineMemory(_timelineCacheKey(requestedSessionId), events);
    final usageScope = _cacheScope;
    if (usageScope != null) {
      unawaited(
        _sessionCache.rememberUsage(
          usageScope,
          requestedSessionId,
          merged,
          session: sessions.firstWhereOrNull(
            (session) => session.id == requestedSessionId,
          ),
        ),
      );
    }
    _queueTimelineCacheReplace(requestedSessionId);
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
      final candidateId = _turnIdFromTurn(candidate);
      final latestId = latest == null ? null : _turnIdFromTurn(latest);
      final noTimestamps = candidateTime == null && latestTime == null;
      // Recent App Server builds include lifecycle timestamps, but older
      // paginated snapshots may omit them. Turn ids are ULID-like and sort in
      // creation order; when even those are unavailable, retain the server's
      // array order (the connector requests ascending turns).
      final newerWithoutTimestamp = noTimestamps
          ? candidateId != null && latestId != null
                ? candidateId.compareTo(latestId) > 0
                : true
          : false;
      final shouldReplace =
          latest == null ||
          (candidateIsActive && !latestIsActive) ||
          (candidateIsActive == latestIsActive &&
              (noTimestamps
                  ? newerWithoutTimestamp
                  : latestTime == null ||
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
    final fileDiffs = isFileChange
        ? TurnFileChanges.fromItem(item)
        : const <String, String>{};
    if (isFileChange) {
      text = fileDiffs.isNotEmpty
          ? TurnFileChanges.numstat(fileDiffs)
          : _extractFileChangePaths(item).join('\n');
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
      phase: _readString(item['phase']),
      fileDiffs: fileDiffs,
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

  /// Relay emits one canonical event vocabulary. Keep this boundary strict so
  /// an unsupported App Server build is visible as a protocol mismatch
  /// instead of being guessed into a lifecycle transition.
  String _normalizeCodexEventType(String rawType) {
    final normalized = rawType.trim();
    return switch (normalized) {
      'thread.created' => 'thread.created',
      'thread/started' => 'thread.created',
      'thread.settings.updated' ||
      'thread/settings/updated' => 'thread.settings.updated',
      'thread.updated' => 'thread.updated',
      'thread/status/changed' => 'thread.updated',
      'thread.queue.changed' => 'thread.queue.changed',
      'thread/queue/changed' => 'thread.queue.changed',
      'turn.started' => 'turn.started',
      'turn/started' => 'turn.started',
      'turn.completed' => 'turn.completed',
      'turn/completed' => 'turn.completed',
      'message.assistant.delta' => 'message.assistant.delta',
      'item/agentMessage/delta' => 'message.assistant.delta',
      'reasoning.delta' => 'reasoning.delta',
      'item/reasoning/summaryTextDelta' => 'reasoning.delta',
      'tool.output' => 'tool.output',
      'item/commandExecution/outputDelta' => 'tool.output',
      'diff.updated' => 'diff.updated',
      'turn/diff/updated' => 'diff.updated',
      'item/fileChange/outputDelta' => 'diff.updated',
      'item.started' => 'item.started',
      'item/started' => 'item.started',
      'item.updated' => 'item.updated',
      'item/updated' => 'item.updated',
      'item.completed' => 'item.completed',
      'item/completed' => 'item.completed',
      'usage.updated' => 'usage.updated',
      'thread/tokenUsage/updated' => 'usage.updated',
      'approval.requested' => 'approval.requested',
      'interaction.resolved' => 'interaction.resolved',
      'error' => 'error',
      _ => '',
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
    // Relay v1 always wraps a normalized notification in `event`. Do not
    // unwrap legacy shapes here: accepting them makes a stale connector look
    // healthy while silently bypassing the current lifecycle contract.
    final event = _asMap(message['event']);
    if (event == null) return;
    final rawType = _readString(event['type']) ?? '';
    final type = _normalizeCodexEventType(rawType);
    if (type.isEmpty) return;
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
    final eventUsage =
        (nestedTurn == null
            ? null
            : readTokenUsage(nestedTurn, scope: TokenUsageScope.turn)) ??
        _extractTokenUsage(data);
    final eventContextUsage =
        (nestedTurn == null ? null : readContextWindowUsage(nestedTurn)) ??
        readContextWindowUsage(data);
    final explicitThreadId =
        _readString(message['threadId']) ??
        _readString(message['thread_id']) ??
        _readString(event['threadId']) ??
        _readString(event['thread_id']) ??
        _readString(data['threadId']) ??
        _readString(data['thread_id']) ??
        _readString(_asMap(data['thread'])?['id']) ??
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
    if (type == 'thread.settings.updated') {
      _applyThreadComposerSettings(explicitThreadId, data);
      return;
    }
    final updatesCatalog =
        type == 'thread.created' ||
        type == 'thread.updated' ||
        type == 'thread.queue.changed';
    // A blank transcript is an intentional new-conversation state. Ignore
    // unscoped/background turn output until the pending new thread is
    // selected, but keep catalog lifecycle events so a desktop-created task
    // appears in the sidebar immediately instead of waiting for the poll.
    if ((selectedId == null || selectedId.isEmpty) &&
        !_pendingSessionStart &&
        !updatesCatalog) {
      return;
    }
    if (threadId != null && threadId.isNotEmpty) {
      if (selectedId != null &&
          selectedId.isNotEmpty &&
          threadId != selectedId) {
        if (!updatesCatalog) return;
      }
    }
    final terminalStatus = type == 'turn.completed'
        ? _terminalStatusFromTurnEvent(type, turnData)
        : TimelineTaskStatus.unknown;
    if (type == 'turn.completed') {
      if (explicitThreadId == null && eventTurnId == null) {
        // Terminal notifications without either thread or turn context are
        // not attributable to the selected task.  Accepting one would make
        // an unrelated/late event paint the conversation as interrupted.
        return;
      }
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
        currentSessionId.value == null &&
        (!updatesCatalog || selectedId == threadId)) {
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
        } else if (timelineStatus.value.isTerminal) {
          // Keep the previous terminal id as a tombstone while promoting the
          // unscoped live delta to an active state. A delayed terminal event
          // for that old id must still be rejected.
          _currentTurnId = null;
          _timelineSnapshotGuard.clearTurnIdentity();
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
        turnId: eventTurnId,
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
      case 'thread.queue.changed':
        // A prompt sent from Codex desktop is represented by a queue change,
        // not an assistant delta. Re-read the selected thread so the new user
        // bubble and the latest turn output appear without waiting for the
        // next heartbeat.
        if (threadId != null && threadId.isNotEmpty && selectedId == threadId) {
          _requestTimelineRead(threadId, force: true);
        } else if (selectedId == null || selectedId.isEmpty) {
          // No task is open yet; refresh only the sidebar catalog and avoid
          // implicitly opening a background conversation in the transcript.
          _sendCommand('thread.list', {'limit': 100});
        }
      case 'turn.started':
        // A new start replaces the tombstoned id from the previous turn. If
        // this older App Server variant omits the id, clear the tombstone so
        // subsequent unscoped events are not mistaken for stale events.
        _currentTurnId =
            eventTurnId ??
            (timelineStatus.value.isTerminal ? null : _currentTurnId);
        if (timelineStatus.value.isTerminal && eventTurnId == null) {
          _timelineSnapshotGuard.clearTurnIdentity();
        }
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
            turnId: eventTurnId,
          );
          _markSessionRunningForNotification(threadId);
          _requestTimelineRead(threadId, force: true);
        }
        _appendSessionEvent(
          SessionEvent(
            kind: 'running',
            text: 'Codex 正在执行...',
            time: startedAt,
            turnId: eventTurnId,
          ),
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
      case 'usage.updated':
        final usageTurnId = eventTurnId ?? _currentTurnId;
        if ((eventUsage != null || eventContextUsage != null) &&
            usageTurnId != null) {
          _appendSessionEvent(
            SessionEvent(
              kind: 'token_usage',
              text: '',
              usage: eventUsage,
              contextWindowUsage: eventContextUsage,
              turnId: usageTurnId,
              itemId:
                  'turn-usage:$usageTurnId:${eventUsage?.scope.name ?? 'context'}',
            ),
          );
        }
      case 'diff.updated':
        final diff = _readString(data['diff']);
        final diffTurnId = eventTurnId ?? _currentTurnId;
        if (diff != null && diffTurnId != null) {
          final fileDiffs = TurnFileChanges.fromUnifiedDiff(diff);
          final numstat = TurnFileChanges.numstat(fileDiffs);
          gitSnapshot.value = GitSnapshot(
            branch: '',
            status: '',
            stat: '',
            numstat: numstat,
            diff: diff,
            log: '',
            fileDiffs: fileDiffs,
          );
          _appendSessionEvent(
            SessionEvent(
              kind: 'git_change',
              text: numstat.isEmpty ? diff : numstat,
              fileDiffs: fileDiffs,
              itemId: 'turn-diff:$diffTurnId',
              turnId: diffTurnId,
            ),
          );
        } else {
          final item = _asMap(data['item']) ?? data;
          final fileDiffs = TurnFileChanges.fromItem(item);
          if (fileDiffs.isNotEmpty) {
            _appendSessionEvent(
              SessionEvent(
                kind: 'file_change',
                text: TurnFileChanges.numstat(fileDiffs),
                fileDiffs: fileDiffs,
                itemId: _eventItemId(data) ?? _eventItemId(event),
                turnId: eventTurnId,
                isDelta: true,
              ),
            );
          }
        }
      case 'item.started':
      case 'item.updated':
      case 'item.completed':
        final snapshot = _eventFromCodexItem(
          _asMap(data['item']) ?? data,
          turnId: eventTurnId,
        );
        if (snapshot != null) {
          _appendSessionEvent(snapshot);
          _refreshGitSnapshotFromEvents(events);
        }
      case 'turn.completed':
        // Codex reports every terminal outcome through `turn/completed`; the
        // nested turn status distinguishes a normal completion from a
        // cancellation or server failure.  A turn that is still active is
        // never allowed to fall through and paint the timeline as complete.
        final completionStatus = _terminalStatusFromTurnEvent(type, turnData);
        if (completionStatus.isActive) return;
        if (_shouldIgnoreTerminalLifecycle(
          threadId: threadId,
          turnId: eventTurnId,
          status: completionStatus,
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
        final completedTurnId = eventTurnId ?? _currentTurnId;
        final terminalItemId = completedTurnId == null
            ? null
            : 'turn-end:$completedTurnId';
        if (completionStatus == TimelineTaskStatus.failed) {
          final message = text.isEmpty ? 'Codex 任务失败' : text;
          _appendSessionEvent(
            SessionEvent(
              kind: 'error',
              text: message,
              time: completedTurnAt,
              completedAt: completedTurnAt,
              turnId: completedTurnId,
              itemId: terminalItemId,
              durationMs: completedDurationMs,
              usage: eventUsage,
              contextWindowUsage: eventContextUsage,
            ),
          );
          _finishCurrentSession(
            status: TaskNotificationStatus.failed,
            sessionId: threadId,
            message: message,
          );
        } else if (completionStatus == TimelineTaskStatus.interrupted) {
          _appendSessionEvent(
            SessionEvent(
              kind: 'interrupted',
              text: text.isEmpty ? '已被用户中断。' : text,
              time: completedTurnAt,
              completedAt: completedTurnAt,
              turnId: completedTurnId,
              itemId: terminalItemId,
              durationMs: completedDurationMs,
              usage: eventUsage,
              contextWindowUsage: eventContextUsage,
            ),
          );
          _finishCurrentSession(
            status: TaskNotificationStatus.interrupted,
            sessionId: threadId,
          );
        } else {
          _appendSessionEvent(
            SessionEvent(
              kind: 'done',
              text: text.isEmpty ? 'Codex 任务已完成' : text,
              time: completedTurnAt,
              completedAt: completedTurnAt,
              turnId: completedTurnId,
              itemId: terminalItemId,
              durationMs: completedDurationMs,
              usage: eventUsage,
              contextWindowUsage: eventContextUsage,
            ),
          );
          _finishCurrentSession(
            status: TaskNotificationStatus.completed,
            sessionId: threadId,
          );
        }
      case 'approval.requested':
        final item = PendingInteraction.fromJson(event);
        if (item.id.isEmpty || item.threadId != selectedId) break;
        _interactionRevision++;
        pendingInteractions[item.id] = item;
        if (item.params['isBlocking'] != false) {
          _setTimelineStatus(
            item.kind == 'userInput'
                ? TimelineTaskStatus.waitingUserInput
                : TimelineTaskStatus.waitingApproval,
            activeFlags: [
              item.kind == 'userInput'
                  ? 'waitingOnUserInput'
                  : 'waitingOnApproval',
            ],
          );
        }
      case 'interaction.resolved':
        _interactionRevision++;
        final id = _readString(event['approvalId']);
        pendingInteractions.remove(id);
        submittedInteractions.remove(id);
        _reconcileSelectedTask();
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
    interactionNotice.value = '';
    _interactionRevision++;
    pendingInteractions.removeWhere((_, item) => item.threadId == id);
    submittedInteractions.removeWhere(
      (key) => !pendingInteractions.containsKey(key),
    );
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
    _queueCatalogCacheWrite();
    _sendCommand('thread.list', {'limit': 100});
  }

  void _applyHostStatus(Object? value) {
    final map = _asMap(value);
    if (map == null) return;
    if (!_adoptEventStream(map['eventStreamId'])) return;
    final appServer = _asMap(map['appServer']) ?? map;
    final state = _readString(appServer['state']);
    if (state != null) {
      final latestSequence = _asMap(map['protocol'])?['latestSequence'];
      if (state == 'ready' &&
          latestSequence is num &&
          latestSequence > _eventRecovery.sequence) {
        _requestEventRecovery();
      }
      final wasReady = backendReady.value;
      backendReady.value = state == 'ready';
      if (!backendReady.value) {
        interactionNotice.value = '执行后端正在恢复连接，任务状态待确认…';
        cacheStale.value = true;
      } else if (!wasReady) {
        interactionNotice.value = '';
        _reconcileSelectedTask();
      }
    }
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
    final id = _composerSettingsThreadId();
    if (id != null) _showThreadComposerSettings(id);
  }

  void _clearRemoteModels() {
    _threadComposerSettings.clear();
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
    String? interactionId,
    Completer<bool>? completion,
  }) {
    if (!connected.value ||
        targetDeviceId.value.isEmpty ||
        spaceId.value.isEmpty) {
      return false;
    }
    _expirePendingCommands();
    // Timeline reads are reconciliation reads.  Do not implicitly resume a
    // historical thread here: an official desktop task may still be owned by
    // the desktop App Server, and attempting `thread/resume` would contend
    // for its writer.  Relay-created tasks are already subscribed when they
    // are created; desktop-owned tasks converge through persisted snapshots.
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
      interactionRevision: _interactionRevision,
      interactionId: interactionId,
      completion: completion,
      settingsStreamId: _eventRecovery.streamId,
      composerPatch: type == 'thread.settings.update'
          ? Map<String, dynamic>.from(command)
          : null,
    );
    final sent = _sendRaw(
      RelayProtocol.command(
        requestId: requestId,
        spaceId: spaceId.value,
        deviceId: deviceId.value,
        targetDeviceId: targetDeviceId.value,
        sequence: _outgoingSequence,
        command: {
          'type': type,
          ...command,
          if (type == 'thread.read' &&
              !force &&
              !timelineLoading.value &&
              _timelineSnapshotHashSessionId == threadId &&
              _timelineSnapshotHash != null &&
              _timelineSnapshotHashReceivedAt != null &&
              DateTime.now().difference(_timelineSnapshotHashReceivedAt!) <
                  const Duration(minutes: 1))
            'snapshotHash': _timelineSnapshotHash,
        },
        threadId: threadId,
        turnId: turnId,
      ),
    );
    if (!sent) _pendingCommands.remove(requestId);
    if (sent && type == 'thread.read') {
      _lastTimelineReadRequestedAt = DateTime.now();
    }
    return sent;
  }

  bool _coalescesPendingCommand(String type) {
    return type == 'thread.list' ||
        type == 'project.list' ||
        type == 'thread.read' ||
        type == 'thread.status' ||
        type == 'sync.request';
  }

  bool _isTransientSyncError(String message) {
    return message.contains('APP_SERVER_TIMEOUT') ||
        message.contains('APP_SERVER_UNAVAILABLE') ||
        message.contains('项目列表同步超时');
  }

  void _markUnconfirmedWrites() {
    for (final pending in _pendingCommands.values) {
      if (!{
        'thread.create',
        'thread.settings.update',
        'turn.start',
        'turn.steer',
        'turn.interrupt',
        'approval.respond',
        'userInput.respond',
      }.contains(pending.kind)) {
        continue;
      }
      if (pending.completion?.isCompleted == false) {
        pending.completion!.complete(false);
      }
      lastError.value = '连接中断，命令结果尚未确认；恢复后请核对任务，勿重复发送。';
      if (pending.kind == 'thread.create') {
        _pendingSessionStart = false;
        _pendingPrompt = null;
      }
    }
  }

  void _expirePendingCommands() {
    final cutoff = DateTime.now().subtract(_commandTimeout);
    var catalogTimedOut = false;
    String? timelineTimedOutSessionId;
    _pendingCommands.removeWhere((_, pending) {
      final expired = pending.sentAt.isBefore(cutoff);
      if (expired && pending.kind == 'sync.request') {
        _syncRecoveryInFlight = false;
      }
      if (expired &&
          {
            'thread.create',
            'thread.settings.update',
            'turn.start',
            'turn.steer',
            'turn.interrupt',
            'approval.respond',
            'userInput.respond',
          }.contains(pending.kind)) {
        if (pending.completion?.isCompleted == false) {
          pending.completion!.complete(false);
        }
        lastError.value = '命令回执超时，执行结果尚未确认；请刷新任务核对，勿重复发送。';
        if (pending.kind == 'thread.create') {
          _pendingSessionStart = false;
          _pendingPrompt = null;
        }
        scheduleMicrotask(_reconcileSelectedTask);
      }
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (connected.value) _sendRaw(RelayProtocol.ping());
    });
  }

  Map<String, dynamic>? _asMap(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  /// Returns the canonical parameter object carried by a Relay event.
  Map<String, dynamic> _codexEventData(Map<String, dynamic> event) {
    return _asMap(event['data']) ?? const <String, dynamic>{};
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
      timed[lastIndex] = timed[lastIndex].copyWith(
        time: resolvedEnd,
        completedAt: resolvedEnd,
      );
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
      'diff',
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
    return readTokenUsage(map);
  }

  int? _readIntValue(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  int? _snapshotRevisionFromValue(Object? value) {
    final map = _asMap(value);
    if (map == null) return null;
    final raw =
        map['snapshotRevision'] ?? map['snapshot_revision'] ?? map['revision'];
    final revision = _readIntValue(raw);
    return revision != null && revision >= 0 ? revision : null;
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

  void _handleDone({WebSocket? socket, int? attempt}) {
    if (socket != null &&
        attempt != null &&
        !_isCurrentSocket(socket, attempt)) {
      return;
    }
    final wasConnected = connected.value;
    _markUnconfirmedWrites();
    final rotating = _tokenRotationInProgress;
    _markTokenRefreshNeededIfExpired();
    _finishTimelineRefresh(error: '任务刷新失败：Relay 连接已断开。');
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _finishHealthCheck('Relay 连接已断开，请重试。');
    connected.value = false;
    connectionLabel.value = 'offline';
    cacheStale.value = true;
    _clearRemoteModels();
    if (timelineLoading.value) {
      _failTimelineLoad('Relay 连接已断开，任务对话未加载完成，请重试。');
    }
    if (wasConnected &&
        !rotating &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
    _socket = null;
    _socketSubscription = null;
    if (rotating) {
      _tokenRotationInProgress = false;
      return;
    }
    _scheduleReconnect(
      force: _forceTokenRefresh && endpointGrant.value.isNotEmpty,
      reason: 'Relay 连接已断开。',
    );
  }

  void _handleSocketError(Object error, {WebSocket? socket, int? attempt}) {
    if (socket != null &&
        attempt != null &&
        !_isCurrentSocket(socket, attempt)) {
      return;
    }
    final wasConnected = connected.value;
    _markUnconfirmedWrites();
    final rotating = _tokenRotationInProgress;
    _markTokenRefreshNeededIfExpired();
    _finishTimelineRefresh(error: '任务刷新失败：Relay 连接异常，请重试。');
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _finishHealthCheck(_connectionTestError(error));
    connected.value = false;
    connectionLabel.value = 'failed';
    cacheStale.value = true;
    _clearRemoteModels();
    if (timelineLoading.value) {
      _failTimelineLoad('Relay 连接异常，任务对话加载失败，请重试。');
    }
    _fail(_connectionTestError(error));
    if (wasConnected &&
        !rotating &&
        !_manualDisconnect &&
        Get.isRegistered<TaskNotificationController>()) {
      unawaited(
        Get.find<TaskNotificationController>().notifyRelayDisconnected(),
      );
    }
    if (rotating) {
      _tokenRotationInProgress = false;
      return;
    }
    _scheduleReconnect(
      force: _forceTokenRefresh && endpointGrant.value.isNotEmpty,
      reason: _connectionTestError(error),
    );
  }

  void _refreshLiveTimeline({
    bool force = false,
    int? refreshToken,
    bool includeCatalog = false,
  }) {
    if (!connected.value) return;
    var listSent = false;
    if (includeCatalog || force) {
      listSent = _sendCommand(
        'thread.list',
        {'limit': 100},
        force: force,
        refreshToken: refreshToken,
      );
    }

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

    // Always poll the compact status for the selected task. The catalog may
    // briefly expose `notLoaded`/an older terminal row while the host is
    // already processing a new turn, and a full thread.read is too expensive
    // to use as that heartbeat for large histories.
    final statusSent = _sendCommand(
      'thread.status',
      {},
      threadId: selectedId,
      force: force,
      refreshToken: refreshToken,
    );
    final selectedIsRunning = sessions.any(
      (session) => session.id.trim() == selectedId && session.isRunning,
    );
    final lastRead = _lastTimelineReadRequestedAt;
    final activeReadDue =
        timelineStatus.value.isActive &&
        (lastRead == null ||
            DateTime.now().difference(lastRead) >= _activeTimelineReadInterval);
    final shouldRead =
        force ||
        timelineLoading.value ||
        activeReadDue ||
        selectedIsRunning && lastRead == null;
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
    if (force && !listSent && !readSent && !statusSent) {
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
      _timelineSnapshotGuard.reset();
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
      _timelineSnapshotGuard.reset();
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
      _timelineSnapshotGuard.reset();
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
      _timelineSnapshotGuard.reset();
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

  WorkspaceInfo? _workspaceForSession(SessionRecord sessionRecord) {
    final projectId = sessionRecord.projectId.trim();
    if (projectId.isNotEmpty) {
      for (final workspace in workspaces) {
        if (workspace.id.trim() == projectId) return workspace;
      }
    }
    final sessionWorkspace = sessionRecord.workspace;
    final normalized = _normalizeWorkspaceKey(sessionWorkspace);
    if (normalized.isEmpty) return null;
    for (final workspace in workspaces) {
      if (workspace.roots.any(
            (root) => _normalizeWorkspaceKey(root) == normalized,
          ) ||
          _normalizeWorkspaceKey(workspace.path) == normalized ||
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
    if (left.id.isNotEmpty && right.id.isNotEmpty) {
      return left.id == right.id;
    }
    final leftPaths = [
      left.path,
      ...left.roots,
    ].map(_normalizeWorkspaceKey).where((path) => path.isNotEmpty).toSet();
    final rightPaths = [
      right.path,
      ...right.roots,
    ].map(_normalizeWorkspaceKey).where((path) => path.isNotEmpty).toSet();
    if (leftPaths.any(rightPaths.contains)) {
      return true;
    }
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
            projectId: workspace.id,
            sessionProjectId: session.projectId,
            workspaceRoots: workspace.roots,
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
        projectId: workspace.id,
        sessionProjectId: session.projectId,
        workspaceRoots: workspace.roots,
        allowBasename: true,
      );
    }).toList();
  }

  void _refreshGitSnapshotFromEvents(Iterable<SessionEvent> source) {
    final fileDiffs = <String, String>{};
    for (final event in source) {
      fileDiffs.addAll(event.fileDiffs);
    }
    if (fileDiffs.isEmpty) return;
    gitSnapshot.value = GitSnapshot(
      branch: '',
      status: '',
      stat: '',
      numstat: TurnFileChanges.numstat(fileDiffs),
      diff: fileDiffs.values.where((value) => value.isNotEmpty).join('\n'),
      log: '',
      fileDiffs: fileDiffs,
    );
  }

  void _appendSessionEvent(SessionEvent event) {
    // Relay frames do not always include a timestamp. Stamp live events at
    // the controller boundary so the answer header can show the elapsed
    // duration just like the desktop client.
    if (event.time == null) {
      event = event.copyWith(time: DateTime.now());
    }
    // A single tool/output item can be much larger than the timeline window.
    // Cap the retained Dart string while the complete payload remains in the
    // durable App Server history.
    if (event.text.length > _maxInMemoryEventTextChars) {
      event = event.copyWith(
        text: '${event.text.substring(0, _maxInMemoryEventTextChars)}\n…',
      );
    }
    // Empty deltas are lifecycle notifications, not visible transcript
    // content. Ignore them so a heartbeat cannot create blank answer cards.
    if (event.text.isEmpty &&
        event.attachments.isEmpty &&
        event.usage == null &&
        event.contextWindowUsage == null &&
        event.phase == null &&
        event.kind != 'running' &&
        event.kind != 'done' &&
        event.kind != 'interrupted' &&
        event.kind != 'git_change' &&
        event.fileDiffs.isEmpty) {
      return;
    }
    // Live stream events are valid content as well. If they arrive before a
    // pending thread.read response, stop showing the hydration spinner while
    // keeping the eventual read response free to merge historical events.
    if (timelineLoading.value) _finishTimelineLoad();
    if (event.kind == 'running') {
      final last = events.isEmpty ? null : events.last;
      if (last?.kind == 'running' && last?.turnId == event.turnId) {
        events[events.length - 1] = event;
        _bumpTimelineRevision();
        _queueTimelineCacheWrite(
          selectedSessionId.value ?? currentSessionId.value,
        );
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
        _trimVisibleTimeline();
        _bumpTimelineRevision();
        _queueTimelineCacheWrite(
          selectedSessionId.value ?? currentSessionId.value,
        );
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
          _trimVisibleTimeline();
          _bumpTimelineRevision();
          _queueTimelineCacheWrite(
            selectedSessionId.value ?? currentSessionId.value,
          );
        }
        return;
      }
    }
    if (event.kind == 'user') {
      // The live user item can arrive before the first thread.read snapshot.
      // Reuse the same temporary-prompt bridge as snapshot merging so the
      // initial local bubble is upgraded with the persisted turn id.
      final similarIndex = _similarEventIndex(events, event);
      if (similarIndex >= 0) {
        final existing = events[similarIndex];
        final merged = _mergeSnapshotEvent(existing, event);
        if (!_sameTimelineEvent(existing, merged)) {
          events[similarIndex] = merged;
          _bumpTimelineRevision();
          _queueTimelineCacheWrite(
            selectedSessionId.value ?? currentSessionId.value,
          );
        }
        return;
      }
    }
    if (_isAnswerMetadata(event) && event.turnId != null) {
      final hasTurn = events.any((item) => item.turnId == event.turnId);
      if (hasTurn) {
        insertAnswerMetadata(events, event);
      } else if (event.turnId == _currentTurnId) {
        events.add(event);
      } else {
        return;
      }
    } else {
      insertEventInTurn(events, event);
    }
    _trimVisibleTimeline();
    _bumpTimelineRevision();
    _queueTimelineCacheWrite(selectedSessionId.value ?? currentSessionId.value);
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
    String projectId = '',
    String sessionProjectId = '',
    List<String> workspaceRoots = const [],
    required bool allowBasename,
  }) {
    if (projectId.trim().isNotEmpty &&
        sessionProjectId.trim() == projectId.trim()) {
      return true;
    }
    final session = _normalizeWorkspaceKey(sessionWorkspace);
    if (session.isEmpty) return false;
    if (workspaceRoots.any((root) => _normalizeWorkspaceKey(root) == session)) {
      return true;
    }
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
    final loadedTurns = loadedEvents
        .map((event) => event.turnId)
        .whereType<String>()
        .toSet();
    for (final event in events) {
      // Omitted older turns have left the history window. Do not resurrect
      // their cached tools/diffs under the newest answer. A newer live turn
      // may be absent from an in-flight read and must still be retained.
      if (loadedTurns.isNotEmpty &&
          event.turnId != null &&
          !loadedTurns.contains(event.turnId) &&
          event.turnId != _currentTurnId) {
        continue;
      }
      if (event.kind == 'running' &&
          (!timelineStatus.value.isActive ||
              loadedEvents.any((item) => item.kind == 'running'))) {
        continue;
      }
      if (event.kind == 'reconnecting' &&
          connected.value &&
          event.text != '连接已恢复') {
        // Successful hydration also repairs retry warnings stored by older
        // clients, even if no new disconnect occurs in this process.
        continue;
      }
      if (_isAnswerMetadata(event)) {
        final index = _eventIdentityIndex(merged, event);
        if (index >= 0) {
          // Prefer authoritative history, retaining locally observed fields
          // only when that history omits them.
          merged[index] = _mergeSnapshotEvent(event, merged[index]);
        } else {
          insertAnswerMetadata(merged, event);
        }
        continue;
      }
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
      // Use a surviving following item as an ordering anchor. This retains
      // commentary/tool interleaving when history omits a live-only item.
      final sourceIndex = events.indexOf(event);
      var before = -1;
      for (var i = sourceIndex + 1; i < events.length; i++) {
        if (events[i].turnId != event.turnId) continue;
        before = _eventIdentityIndex(merged, events[i]);
        if (before >= 0) break;
      }
      if (before >= 0) {
        merged.insert(before, event);
      } else {
        insertEventInTurn(merged, event);
      }
    }
    return orderTimelineEvents(merged);
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
      completedAt: delta.completedAt ?? existing.completedAt,
      usage: delta.usage ?? existing.usage,
      contextWindowUsage: newerContextWindowUsage(
        existing.contextWindowUsage,
        delta.contextWindowUsage,
      ),
      attachments: _mergeEventAttachments(
        existing.attachments,
        delta.attachments,
      ),
      itemId: existing.itemId ?? delta.itemId,
      turnId: existing.turnId ?? delta.turnId,
      phase: delta.phase ?? existing.phase,
      isDelta: true,
    );
  }

  SessionEvent _mergeSnapshotEvent(
    SessionEvent existing,
    SessionEvent snapshot,
  ) {
    // Transport states replace one another; a shorter recovery label must
    // replace the longer retry/error text rather than losing to text length.
    if (snapshot.kind == 'git_change' ||
        snapshot.kind == 'reconnecting' ||
        snapshot.kind == 'running') {
      return snapshot;
    }
    final nextText = _preferSnapshotText(existing.text, snapshot.text);
    return existing.copyWith(
      text: nextText,
      time: existing.time ?? snapshot.time,
      durationMs: snapshot.durationMs ?? existing.durationMs,
      completedAt: snapshot.completedAt ?? existing.completedAt,
      usage: snapshot.usage ?? existing.usage,
      contextWindowUsage: newerContextWindowUsage(
        existing.contextWindowUsage,
        snapshot.contextWindowUsage,
      ),
      attachments: _mergeEventAttachments(
        existing.attachments,
        snapshot.attachments,
      ),
      itemId: existing.itemId ?? snapshot.itemId,
      turnId: existing.turnId ?? snapshot.turnId,
      phase: snapshot.phase ?? existing.phase,
      isDelta: existing.isDelta || snapshot.isDelta,
      fileDiffs: snapshot.fileDiffs.isNotEmpty
          ? snapshot.fileDiffs
          : existing.fileDiffs,
    );
  }

  String _appendDeltaText(String current, String delta) {
    // Duplicate frames are rejected by event stream id/sequence before here.
    // Repeated words, spaces and punctuation are valid incremental content.
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
        a.time?.toUtc() != b.time?.toUtc() ||
        a.durationMs != b.durationMs ||
        a.completedAt?.toUtc() != b.completedAt?.toUtc() ||
        a.itemId != b.itemId ||
        a.turnId != b.turnId ||
        a.phase != b.phase ||
        a.isDelta != b.isDelta ||
        jsonEncode(a.fileDiffs) != jsonEncode(b.fileDiffs) ||
        !_sameTokenUsage(a.usage, b.usage) ||
        a.contextWindowUsage != b.contextWindowUsage ||
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

  bool _sameTokenUsage(TokenUsage? left, TokenUsage? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.inputTokens == right.inputTokens &&
        left.outputTokens == right.outputTokens &&
        left.totalTokens == right.totalTokens &&
        left.scope == right.scope &&
        left.hasBreakdown == right.hasBreakdown &&
        left.cachedInputTokens == right.cachedInputTokens &&
        left.reasoningOutputTokens == right.reasoningOutputTokens;
  }

  bool _isAnswerMetadata(SessionEvent event) =>
      event.kind == 'token_usage' ||
      event.kind == 'done' ||
      event.completedAt != null &&
          event.itemId?.startsWith('turn-end:') == true;

  bool _isLiveStatusEvent(SessionEvent event) {
    return event.kind == 'user' && event.turnId != null ||
        event.kind == 'running' ||
        event.kind == 'reconnecting' ||
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
      // Text is not an identity across turns or distinct protocol items.
      // Repeated commentary (e.g. "正在检查") is valid content.
      if (candidate.turnId != event.turnId) continue;
      if (candidate.itemId?.isNotEmpty == true &&
          event.itemId?.isNotEmpty == true &&
          candidate.itemId != event.itemId) {
        continue;
      }
      if (candidate.phase != null &&
          event.phase != null &&
          candidate.phase != event.phase) {
        continue;
      }
      final candidateText = candidate.text.trim();
      // A newly sent prompt is rendered immediately without a turn id. The
      // first persisted snapshot carries the same prompt with its turn id.
      // Treat that pair as one event so hydration does not show the prompt
      // twice. Restrict this bridge to user messages with exact text: two
      // assistant fragments with an omitted id may be legitimate content.
      final candidateTurnId = candidate.turnId?.trim() ?? '';
      final eventTurnId = event.turnId?.trim() ?? '';
      if (candidate.kind == 'user' &&
          candidateText == text &&
          candidateTurnId.isEmpty != eventTurnId.isEmpty) {
        return index;
      }
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
        unawaited(_activateSessionCache());
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
      '自动审查' => 'on-request',
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

  Future<void> _storeConnectionHints({int? expectedAttempt}) async {
    if (expectedAttempt != null && expectedAttempt != _connectionAttempt) {
      return;
    }
    try {
      await initializeStorage();
      if (expectedAttempt != null && expectedAttempt != _connectionAttempt) {
        return;
      }
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
      if (expectedAttempt != null && expectedAttempt != _connectionAttempt) {
        return;
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
        if (workspace.path == defaultWorkspacePath ||
            workspace.roots.contains(defaultWorkspacePath)) {
          return workspace;
        }
      }
    }
    final storedName = _storedWorkspaceName?.trim() ?? '';
    final storedPath = _storedWorkspacePath?.trim() ?? '';
    for (final workspace in workspaces) {
      if (storedPath.isNotEmpty &&
          (workspace.path == storedPath ||
              workspace.roots.contains(storedPath))) {
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

  Future<void> _autoConnect({bool fromReconnect = false}) {
    return connect(
      inputBaseUrl: baseUrl.value,
      token: pairingToken.value,
      inputDeviceName: deviceName.value,
      inputSpaceId: spaceId.value,
      inputTargetDeviceId: targetDeviceId.value,
      inputEndpointId: deviceId.value,
      inputEndpointType: endpointType.value,
      inputEndpointGrant: endpointGrant.value,
      fromReconnect: fromReconnect,
    );
  }

  void _scheduleReconnect({bool force = false, String? reason}) {
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : null;
    if (_manualDisconnect ||
        _credentialRefreshBlocked ||
        !force && preferences != null && !preferences.autoReconnect.value ||
        (pairingToken.value.isEmpty && endpointGrant.value.isEmpty) ||
        spaceId.value.isEmpty ||
        targetDeviceId.value.isEmpty ||
        _reconnectTimer != null) {
      return;
    }
    _reconnectAttemptCount += 1;
    connectionLabel.value = 'reconnecting';
    _appendTransportTimelineEvent(
      '正在重新连接 $_reconnectAttemptCount/5${reason == null || reason.trim().isEmpty ? '' : '\n$reason'}',
    );
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      final currentPreferences =
          Get.isRegistered<SettingsPreferencesController>()
          ? Get.find<SettingsPreferencesController>()
          : null;
      if (!_manualDisconnect &&
          !_credentialRefreshBlocked &&
          !connected.value &&
          (force || (currentPreferences?.autoReconnect.value ?? true)) &&
          (pairingToken.value.isNotEmpty || endpointGrant.value.isNotEmpty) &&
          spaceId.value.isNotEmpty &&
          targetDeviceId.value.isNotEmpty) {
        unawaited(_autoConnect(fromReconnect: true));
      }
    });
  }

  void _appendTransportTimelineEvent(String text) {
    final sessionId = selectedSessionId.value ?? currentSessionId.value;
    if (sessionId == null || sessionId.trim().isEmpty) return;
    final hasActiveTurn =
        timelineStatus.value.isActive ||
        events.any((event) => event.kind == 'running');
    if (!hasActiveTurn) return;
    _appendSessionEvent(
      SessionEvent(
        kind: 'reconnecting',
        text: text,
        itemId: 'transport-reconnect-$sessionId',
        turnId: _currentTurnId,
      ),
    );
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
    if (error is _ConnectTokenRefreshException) {
      return _friendlyRelayError(error.code, error.message);
    }
    final text = error.toString().replaceFirst(
      RegExp(r'^[A-Za-z_]\w*:\s*'),
      '',
    );
    return _friendlyRelayError('', text);
  }

  String _friendlyRelayError(String code, String message) {
    final normalized = '${code.trim()} ${message.trim()}'.toLowerCase();
    if (code == 'RELAY_RETRYABLE' ||
        normalized.contains('relay_retryable') ||
        normalized.contains('temporarily unavailable')) {
      return '连接令牌自动续期暂时失败，将在稍后重试。';
    }
    if (normalized.contains('connection limit exceeded') ||
        normalized.contains('connect token connection limit')) {
      return '连接令牌已达到并发连接上限，请断开其它连接或提高令牌的连接上限。';
    }
    if (code == 'auth.grant_expired' ||
        code == 'auth.grant_revoked' ||
        code == 'auth.invalid_grant' ||
        normalized.contains('auth.grant_expired') ||
        normalized.contains('auth.grant_revoked') ||
        normalized.contains('auth.invalid_grant') ||
        normalized.contains('endpoint grant expired') ||
        normalized.contains('endpoint grant was revoked')) {
      return '接入端授权凭证已失效，请从 Relay 控制台重新签发一组连接凭证。';
    }
    if (code == 'auth.grant_required' ||
        normalized.contains('auth.grant_required')) {
      return '连接令牌已过期。请填写同一次签发的接入端授权凭证，客户端才能自动续期。';
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

  Future<String> _usableConnectToken(
    String suppliedToken, {
    int? attempt,
  }) async {
    final operationAttempt = attempt ?? _connectionAttempt;
    if (suppliedToken.isNotEmpty && suppliedToken != pairingToken.value) {
      pairingToken.value = suppliedToken;
      tokenExpiresAt.value = 0;
      _forceTokenRefresh = false;
    }
    if (_credentialRefreshBlocked) {
      throw StateError('auth.grant_expired');
    }
    final operationGrant = endpointGrant.value;
    final operationRelayUrl = baseUrl.value;
    final hasGrant = operationGrant.isNotEmpty;
    final expiresAt = tokenExpiresAt.value;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tokenIsExpiring =
        expiresAt > 0 && expiresAt <= now + _tokenRefreshLead.inMilliseconds;
    final needsRefresh =
        hasGrant &&
        (pairingToken.value.isEmpty ||
            _forceTokenRefresh ||
            expiresAt <= 0 ||
            tokenIsExpiring);
    if (needsRefresh) {
      try {
        await _refreshConnectTokenOnce(
          attempt: operationAttempt,
          grant: operationGrant,
          relayUrl: operationRelayUrl,
        );
        if (operationAttempt != _connectionAttempt) {
          return pairingToken.value;
        }
      } catch (error) {
        // A refresh belonging to an older pairing must not report an error or
        // schedule work against the newly selected pairing.
        if (operationAttempt != _connectionAttempt) return pairingToken.value;
        final stillUsable =
            !_forceTokenRefresh &&
            pairingToken.value.isNotEmpty &&
            (expiresAt <= 0 || expiresAt > now);
        if (!stillUsable) rethrow;
        if (connected.value) {
          _scheduleTokenRefresh(delay: _refreshRetryDelay(error));
        }
      }
    }
    if (!hasGrant &&
        (_forceTokenRefresh || (expiresAt > 0 && expiresAt <= now))) {
      throw StateError('auth.grant_required');
    }
    if (pairingToken.value.isEmpty) {
      throw StateError('缺少连接令牌');
    }
    return pairingToken.value;
  }

  bool _isCurrentConnectionAttempt(int attempt) {
    return attempt == _connectionAttempt && !_manualDisconnect;
  }

  Future<void> _refreshConnectTokenOnce({
    int? attempt,
    String? grant,
    String? relayUrl,
  }) {
    final operationAttempt = attempt ?? _connectionAttempt;
    final operationGrant = grant ?? endpointGrant.value;
    final operationRelayUrl = relayUrl ?? baseUrl.value;
    final contextKey = [
      operationAttempt,
      operationRelayUrl,
      operationGrant,
    ].join('\u0000');
    final inFlight = _tokenRefreshInFlight;
    if (inFlight != null && _tokenRefreshContextKey == contextKey) {
      return inFlight;
    }
    late Future<void> future;
    future = () async {
      try {
        await _refreshConnectToken(
          attempt: operationAttempt,
          grant: operationGrant,
          relayUrl: operationRelayUrl,
        );
      } finally {
        if (identical(_tokenRefreshInFlight, future)) {
          _tokenRefreshInFlight = null;
          _tokenRefreshContextKey = null;
        }
      }
    }();
    _tokenRefreshInFlight = future;
    _tokenRefreshContextKey = contextKey;
    return future;
  }

  void _scheduleTokenRefresh({Duration? delay}) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    if (!connected.value ||
        _manualDisconnect ||
        _credentialRefreshBlocked ||
        _tokenRotationInProgress ||
        endpointGrant.value.isEmpty) {
      return;
    }
    final expiry = tokenExpiresAt.value;
    final now = DateTime.now().millisecondsSinceEpoch;
    final calculated = expiry <= 0
        ? _unknownTokenRefreshInterval
        : Duration(
            milliseconds: (expiry - now - _tokenRefreshLead.inMilliseconds)
                .clamp(1000, 0x7fffffffffffffff)
                .toInt(),
          );
    _tokenRefreshTimer = Timer(delay ?? calculated, () {
      _tokenRefreshTimer = null;
      unawaited(_runScheduledTokenRefresh());
    });
  }

  Future<void> _runScheduledTokenRefresh() async {
    if (!connected.value ||
        _manualDisconnect ||
        _credentialRefreshBlocked ||
        _tokenRotationInProgress ||
        endpointGrant.value.isEmpty) {
      return;
    }
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    final attempt = _connectionAttempt;
    final grant = endpointGrant.value;
    final relayUrl = baseUrl.value;
    var rotationStarted = false;
    try {
      await _refreshConnectTokenOnce(
        attempt: attempt,
        grant: grant,
        relayUrl: relayUrl,
      );
      if (!connected.value ||
          _manualDisconnect ||
          attempt != _connectionAttempt ||
          endpointGrant.value != grant ||
          !identical(_socket, socket)) {
        return;
      }
      // A Connect Token is part of the first handshake frame, so rotate the
      // WebSocket after a successful refresh. The close is intentional and
      // must not be reported as a network failure.
      _tokenRotationInProgress = true;
      rotationStarted = true;
      connected.value = false;
      connectionLabel.value = 'reconnecting';
      await _closeSocketForRotation(socket);
      // The rotation close is detached from the normal socket callbacks, so
      // finish it here even when the platform omits a close event.
      _tokenRotationInProgress = false;
      if (attempt == _connectionAttempt &&
          !_manualDisconnect &&
          endpointGrant.value == grant &&
          baseUrl.value == relayUrl &&
          !_credentialRefreshBlocked) {
        // Reconnect with the newly minted first-frame token regardless of the
        // ordinary network auto-reconnect preference.
        _scheduleReconnect(force: true);
      }
    } catch (error) {
      if (attempt != _connectionAttempt ||
          endpointGrant.value != grant ||
          baseUrl.value != relayUrl) {
        return;
      }
      if (rotationStarted) {
        _tokenRotationInProgress = false;
        connected.value = false;
        connectionLabel.value = 'reconnecting';
        if (!_manualDisconnect && !_credentialRefreshBlocked) {
          _scheduleReconnect(force: true);
        }
        return;
      }
      if (_isTerminalRefreshFailure(error)) {
        _credentialRefreshBlocked = true;
        _forceTokenRefresh = false;
        _tokenRefreshTimer?.cancel();
        _tokenRefreshTimer = null;
        lastError.value = _connectionTestError(error);
        connectionLabel.value = 'failed';
        _tokenRotationInProgress = true;
        rotationStarted = true;
        connected.value = false;
        try {
          await _closeSocketForRotation(socket);
        } finally {
          _tokenRotationInProgress = false;
        }
        return;
      }
      // Keep the current socket alive during a transient outage. A later
      // attempt (or Relay's token_expired frame) will force the same refresh
      // path again without spinning a reconnect loop.
      lastError.value = '连接令牌自动续期暂时失败，将在稍后重试。';
      _tokenRefreshRetryAttempt += 1;
      _scheduleTokenRefresh(delay: _refreshRetryDelay(error));
    } finally {
      if (rotationStarted) {
        _tokenRotationInProgress = false;
      }
    }
  }

  bool _isTerminalRefreshFailure(Object error) {
    if (_isRetryableRefreshFailure(error)) return false;
    if (error is _ConnectTokenRefreshException && error.terminal) return true;
    final text = error.toString().toLowerCase();
    return text.contains('auth.grant_expired') ||
        text.contains('auth.grant_revoked') ||
        text.contains('auth.invalid_grant') ||
        text.contains('auth.grant_required') ||
        text.contains('auth.account_unavailable') ||
        text.contains('auth.space_unavailable') ||
        text.contains('auth.endpoint_type_mismatch') ||
        text.contains('auth.refresh_invalid') ||
        text.contains('auth.refresh_rejected') ||
        text.contains('auth.proof_') ||
        text.contains('auth_context_changed') ||
        text.contains('invalid_message');
  }

  bool _isRetryableRefreshFailure(Object error) {
    if (error is _ConnectTokenRefreshException) return error.retryable;
    return error.toString().toLowerCase().contains('relay_retryable');
  }

  Duration _refreshRetryDelay(Object error) {
    if (error is _ConnectTokenRefreshException && error.retryAfter != null) {
      final requested = error.retryAfter!;
      return requested < const Duration(milliseconds: 250)
          ? const Duration(milliseconds: 250)
          : requested;
    }
    final exponent = _tokenRefreshRetryAttempt.clamp(0, 3).toInt();
    return _tokenRefreshRetry * (1 << exponent);
  }

  bool _isRefreshableRelayCode(String code) {
    return code == 'auth.token_expired' || code == 'auth.invalid_token';
  }

  void _markTokenRefreshNeededIfExpired() {
    final expiry = tokenExpiresAt.value;
    if (endpointGrant.value.isNotEmpty &&
        (expiry <= 0 ||
            expiry <=
                DateTime.now().millisecondsSinceEpoch +
                    _tokenRefreshLead.inMilliseconds)) {
      _forceTokenRefresh = true;
    } else if (endpointGrant.value.isEmpty &&
        expiry > 0 &&
        expiry <= DateTime.now().millisecondsSinceEpoch) {
      _credentialRefreshBlocked = true;
    }
  }

  Future<void> _refreshConnectToken({
    required int attempt,
    required String grant,
    required String relayUrl,
  }) async {
    final keyPair = _keyPair;
    if (keyPair == null || grant.isEmpty) {
      throw StateError('缺少接入端授权凭证或接入端私钥');
    }
    if (grantExpiresAt.value > 0 &&
        grantExpiresAt.value <= DateTime.now().millisecondsSinceEpoch) {
      throw StateError('auth.grant_expired');
    }
    final relay = Uri.parse(relayUrl);
    final refreshed = await _requestConnectToken(
      relay: relay,
      keyPair: keyPair,
      grant: grant,
      expectedSpaceId: spaceId.value,
      expectedEndpointId: deviceId.value,
      expectedEndpointType: endpointType.value,
    );
    // A refresh request can outlive a manual disconnect or pairing switch.
    // Never apply its result to a different connection context.
    if (attempt != _connectionAttempt ||
        _manualDisconnect ||
        _keyPair != keyPair ||
        endpointGrant.value != grant ||
        baseUrl.value != relayUrl) {
      return;
    }
    pairingToken.value = refreshed.token;
    tokenExpiresAt.value = refreshed.expiresAt;
    _forceTokenRefresh = false;
    if (refreshed.grantExpiresAt != null) {
      grantExpiresAt.value = refreshed.grantExpiresAt!;
    }
    _tokenRefreshRetryAttempt = 0;
    await _storeConnectionHints(expectedAttempt: attempt);
  }

  Future<_ConnectTokenRefreshResult> _requestConnectToken({
    required Uri relay,
    required SimpleKeyPair keyPair,
    required String grant,
    required String expectedSpaceId,
    required String expectedEndpointId,
    required String expectedEndpointType,
  }) async {
    if (grant.trim().isEmpty) throw StateError('缺少接入端授权凭证');
    if (!const {'ws', 'wss'}.contains(relay.scheme) ||
        !relay.hasAuthority ||
        relay.userInfo.isNotEmpty ||
        relay.query.isNotEmpty ||
        relay.fragment.isNotEmpty) {
      throw StateError('Relay 连接地址不适合用于 Token 刷新');
    }
    if (relay.scheme == 'ws' && !_isLoopbackHost(relay.host)) {
      throw StateError('非本机 Relay 的 Token 刷新必须使用 HTTPS');
    }
    final endpoint = relay.replace(
      scheme: relay.scheme == 'wss' ? 'https' : 'http',
      path: '/api/connect-tokens/refresh',
      query: '',
      fragment: '',
    );
    if (endpoint.scheme == 'http' && !_isLoopbackHost(endpoint.host)) {
      throw StateError('非本机 Relay 的 Token 刷新必须使用 HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(endpoint);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.add(
        utf8.encode(
          jsonEncode(
            await RelayProtocol.connectTokenRefreshRequest(
              keyPair: keyPair,
              endpointGrant: grant,
            ),
          ),
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bodyText = await response.transform(utf8.decoder).join();
      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(bodyText);
        body = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : const <String, dynamic>{};
      } catch (_) {
        body = const <String, dynamic>{};
      }
      final dataValue = body['data'];
      final data = dataValue is Map
          ? Map<String, dynamic>.from(dataValue)
          : body;
      final relayCode = body['code'];
      final errorCode = data['errorCode'];
      final statusRetryable =
          _isRetryableHttpStatus(response.statusCode) ||
          _isRetryableEnvelopeCode(relayCode);
      final rejected =
          response.statusCode < 200 ||
          response.statusCode >= 300 ||
          (relayCode is num &&
              relayCode.isFinite &&
              relayCode == relayCode.toInt() &&
              relayCode.toInt() != 200);
      if (rejected) {
        final code = errorCode is String && errorCode.trim().isNotEmpty
            ? errorCode.trim()
            : 'auth.refresh_rejected';
        final message = body['msg']?.toString().trim().isNotEmpty == true
            ? body['msg'].toString()
            : 'Connect Token 刷新被拒绝（HTTP ${response.statusCode}）';
        if (statusRetryable) {
          throw _ConnectTokenRefreshException(
            code: 'RELAY_RETRYABLE',
            message: message,
            retryable: true,
            retryAfter: _retryAfterDuration(
              response.headers.value(HttpHeaders.retryAfterHeader),
            ),
          );
        }
        throw _ConnectTokenRefreshException(
          code: code,
          message: message,
          terminal: _isTerminalRefreshCode(code),
        );
      }
      final nextToken = data['connectToken'];
      final now = DateTime.now().millisecondsSinceEpoch;
      final nextExpiresAtInt = _safeRefreshInteger(data['expiresAt']);
      if (nextToken is! String ||
          nextToken.length < 32 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(nextToken) ||
          nextExpiresAtInt == null ||
          nextExpiresAtInt <= now) {
        throw const _ConnectTokenRefreshException(
          code: 'INVALID_MESSAGE',
          message: 'Relay 返回了无效的刷新凭证',
          terminal: true,
        );
      }
      _validateRefreshContext(
        data,
        expectedSpaceId: expectedSpaceId,
        expectedEndpointId: expectedEndpointId,
        expectedEndpointType: expectedEndpointType,
      );
      final hasGrantExpiry = data.containsKey('grantExpiresAt');
      final rawGrantExpiry = data['grantExpiresAt'];
      final nextGrantExpiresAtInt = rawGrantExpiry == null
          ? null
          : _safeRefreshInteger(rawGrantExpiry);
      if (hasGrantExpiry &&
          (rawGrantExpiry == null ||
              nextGrantExpiresAtInt == null ||
              nextGrantExpiresAtInt <= now)) {
        throw const _ConnectTokenRefreshException(
          code: 'INVALID_MESSAGE',
          message: 'Relay 返回了无效的授权凭证有效期',
          terminal: true,
        );
      }
      return _ConnectTokenRefreshResult(
        token: nextToken,
        expiresAt: nextExpiresAtInt,
        grantExpiresAt: nextGrantExpiresAtInt,
      );
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
    if (!uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw FormatException('Relay 连接地址必须是无 query/hash/用户凭证的 WebSocket 地址');
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

class _ConnectTokenRefreshResult {
  const _ConnectTokenRefreshResult({
    required this.token,
    required this.expiresAt,
    this.grantExpiresAt,
  });

  final String token;
  final int expiresAt;
  final int? grantExpiresAt;
}

class _ConnectTokenRefreshException implements Exception {
  const _ConnectTokenRefreshException({
    required this.code,
    required this.message,
    this.retryable = false,
    this.retryAfter,
    this.terminal = false,
  });

  final String code;
  final String message;
  final bool retryable;
  final Duration? retryAfter;
  final bool terminal;

  @override
  String toString() => '$code: $message';
}

const int _maxSafeRefreshInteger = 9007199254740991;
const int _maxRefreshRetryAfterMilliseconds = 10 * 60 * 1000;

int? _safeRefreshInteger(Object? value) {
  if (value is! num || !value.isFinite || value != value.truncate()) {
    return null;
  }
  final asDouble = value.toDouble();
  if (asDouble <= 0 || asDouble > _maxSafeRefreshInteger) return null;
  final integer = value.toInt();
  return integer > 0 && integer <= _maxSafeRefreshInteger ? integer : null;
}

bool _isRetryableHttpStatus(int status) {
  return status == 408 ||
      status == 425 ||
      status == 429 ||
      status >= 500 && status <= 599;
}

bool _isRetryableEnvelopeCode(Object? value) {
  final code = _safeRefreshInteger(value);
  return code != null && _isRetryableHttpStatus(code);
}

Duration? _retryAfterDuration(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(raw)) {
    final seconds = int.tryParse(raw);
    if (seconds == null) {
      return const Duration(milliseconds: _maxRefreshRetryAfterMilliseconds);
    }
    final milliseconds = seconds > _maxRefreshRetryAfterMilliseconds ~/ 1000
        ? _maxRefreshRetryAfterMilliseconds
        : seconds * 1000;
    return Duration(milliseconds: milliseconds);
  }
  DateTime? timestamp;
  try {
    timestamp = HttpDate.parse(raw).toUtc();
  } catch (_) {
    timestamp = DateTime.tryParse(raw)?.toUtc();
  }
  if (timestamp == null) return null;
  final milliseconds = timestamp
      .difference(DateTime.now().toUtc())
      .inMilliseconds
      .clamp(0, _maxRefreshRetryAfterMilliseconds)
      .toInt();
  return Duration(milliseconds: milliseconds);
}

void _validateRefreshContext(
  Map<String, dynamic> data, {
  required String expectedSpaceId,
  required String expectedEndpointId,
  required String expectedEndpointType,
}) {
  final expected = <String, String>{
    'spaceId': expectedSpaceId,
    'endpointId': expectedEndpointId,
    'endpointType': expectedEndpointType,
  };
  for (final entry in expected.entries) {
    if (!data.containsKey(entry.key)) continue;
    final value = data[entry.key];
    if (value is! String || value.isEmpty || value != entry.value) {
      throw _ConnectTokenRefreshException(
        code: 'AUTH_CONTEXT_CHANGED',
        message: 'Relay 刷新响应的 ${entry.key} 与当前配置不一致',
        terminal: true,
      );
    }
  }
}

bool _isTerminalRefreshCode(String code) {
  return {
    'auth.grant_expired',
    'auth.grant_revoked',
    'auth.invalid_grant',
    'auth.grant_required',
    'auth.account_unavailable',
    'auth.space_unavailable',
    'auth.endpoint_type_mismatch',
    'auth.refresh_invalid',
    'auth.refresh_rejected',
    'auth.proof_required',
    'auth.proof_mismatch',
    'auth.proof_invalid',
    'auth.proof_expired',
    'auth.replay',
    'AUTH_CONTEXT_CHANGED',
  }.contains(code);
}

class _ConnectionTestAttempt {
  const _ConnectionTestAttempt({this.error, this.code});

  final String? error;
  final String? code;
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
    this.interactionRevision,
    this.interactionId,
    this.completion,
    this.composerPatch,
    this.settingsStreamId,
  });

  final String kind;
  final String? threadId;
  final String? turnId;
  final DateTime sentAt;
  final int? refreshToken;
  final int? timelineReadGeneration;
  final int? interactionRevision;
  final String? interactionId;
  final Completer<bool>? completion;
  final Map<String, dynamic>? composerPatch;
  final String? settingsStreamId;

  bool matches(String commandKind, {String? threadId}) {
    return kind == commandKind && this.threadId == threadId;
  }
}
