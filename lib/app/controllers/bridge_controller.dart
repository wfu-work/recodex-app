import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../models/bridge_models.dart';

class BridgeController extends GetxController {
  static const _storage = FlutterSecureStorage();

  final baseUrl = 'http://127.0.0.1:8765'.obs;
  final deviceName = 'Flutter phone'.obs;
  final deviceId = 'flutter_${DateTime.now().millisecondsSinceEpoch}'.obs;
  final deviceKey = ''.obs;
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
  final currentSessionId = RxnString();

  WebSocket? _socket;
  int _messageSeq = 0;

  bool get canUseWorkspace => connected.value && selectedWorkspace.value != null;
  bool get hasDeviceKey => deviceKey.value.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadStoredCredentials());
  }

  @override
  void onClose() {
    unawaited(disconnect(silent: true));
    super.onClose();
  }

  Future<void> connect({
    required String inputBaseUrl,
    required String token,
    required String inputDeviceName,
  }) async {
    busy.value = true;
    lastError.value = '';
    connectionLabel.value = 'connecting';

    try {
      await disconnect(silent: true);
      baseUrl.value = _normalizeBaseUrl(inputBaseUrl);
      deviceName.value = inputDeviceName.trim().isEmpty
          ? 'Flutter phone'
          : inputDeviceName.trim();
      final wsUrl = '${baseUrl.value.replaceFirst(RegExp('^http'), 'ws')}/ws';
      _socket = await WebSocket.connect(wsUrl);
      _socket!.listen(
        _handleRawMessage,
        onDone: _handleDone,
        onError: _handleSocketError,
      );
      _send('auth.hello', {
        'deviceId': deviceId.value,
        'deviceName': deviceName.value,
        'deviceKey': deviceKey.value,
        'token': token.trim(),
      });
    } catch (error) {
      _fail(error);
      connectionLabel.value = 'failed';
      connected.value = false;
    } finally {
      busy.value = false;
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close();
    }
    connected.value = false;
    connectionLabel.value = 'offline';
  }

  void selectWorkspace(WorkspaceInfo? workspace) {
    selectedWorkspace.value = workspace;
    gitSnapshot.value = null;
  }

  void startSession(String prompt) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    events.clear();
    currentSessionId.value = null;
    _send('session.start', {'workspace': workspace.name, 'prompt': prompt.trim()});
  }

  void interrupt() {
    final sessionId = currentSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return;
    _send('session.interrupt', {'sessionId': sessionId});
  }

  void gitStatus({required bool includeDiff}) {
    final workspace = selectedWorkspace.value;
    if (workspace == null) return;
    _send(includeDiff ? 'git.diff' : 'git.status', {'workspace': workspace.name});
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

  void revokeDevice(String id) {
    _send('device.revoke', {'deviceId': id});
  }

  Future<void> clearStoredCredentials() async {
    deviceKey.value = '';
    lastError.value = '';
    try {
      await _storage.delete(key: 'recodex_device_key');
    } catch (_) {
      lastError.value = 'Secure storage is unavailable on this target.';
    }
  }

  void _handleRawMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = decoded['type'] as String? ?? '';
      final payload = decoded['payload'];
      final map = payload is Map<String, dynamic> ? payload : <String, dynamic>{};

      switch (type) {
        case 'bridge.hello':
          connectionLabel.value = 'auth';
        case 'auth.ok':
          connected.value = true;
          connectionLabel.value = 'online';
          final newKey = map['deviceKey'] as String? ?? '';
          if (newKey.isNotEmpty) {
            deviceKey.value = newKey;
            unawaited(_storeCredentials());
          }
          _send('workspace.list', {});
          _send('session.list', {});
          _send('device.list', {});
        case 'workspace.list.result':
          workspaces.assignAll(
            ((map['workspaces'] as List?) ?? const [])
                .whereType<Map>()
                .map((item) => WorkspaceInfo.fromJson(item.cast<String, dynamic>())),
          );
          selectedWorkspace.value ??= workspaces.isEmpty ? null : workspaces.first;
        case 'session.list.result':
          sessions.assignAll(
            ((map['sessions'] as List?) ?? const [])
                .whereType<Map>()
                .map((item) => SessionRecord.fromJson(item.cast<String, dynamic>())),
          );
        case 'device.list.result':
          devices.assignAll(
            ((map['devices'] as List?) ?? const [])
                .whereType<Map>()
                .map((item) => DeviceInfo.fromJson(item.cast<String, dynamic>())),
          );
        case 'session.created':
          final record = SessionRecord.fromJson(map);
          currentSessionId.value = record.id;
          sessions.insert(0, record);
        case 'session.event':
          events.add(SessionEvent.fromJson(map));
        case 'session.done':
          events.add(SessionEvent.fromJson(map));
          currentSessionId.value = null;
          _send('session.list', {});
        case 'session.error':
          final message =
              map['message'] as String? ?? map['text'] as String? ?? 'Unknown error';
          lastError.value = message;
          events.add(SessionEvent(kind: 'error', text: message));
          currentSessionId.value = null;
        case 'session.interrupted':
          currentSessionId.value = null;
          events.add(const SessionEvent(kind: 'interrupted', text: 'Interrupted by user.'));
        case 'git.status.result':
        case 'git.diff.result':
          gitSnapshot.value = GitSnapshot.fromJson(map);
        case 'device.revoke.result':
          final revokedId = map['deviceId'] as String? ?? '';
          devices.removeWhere((device) => device.id == revokedId);
          if (revokedId == deviceId.value) {
            deviceKey.value = '';
            connectionLabel.value = 'revoked';
            unawaited(disconnect());
          }
        case 'confirm.required':
          lastError.value = map['message'] as String? ?? 'Confirmation required.';
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
  }

  void _handleSocketError(Object error) {
    connected.value = false;
    connectionLabel.value = 'failed';
    _fail(error);
  }

  void _send(String type, Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    _messageSeq += 1;
    socket.add(jsonEncode({'type': type, 'id': 'm_$_messageSeq', 'payload': payload}));
  }

  Future<void> _loadStoredCredentials() async {
    try {
      final storedDeviceId = await _storage.read(key: 'recodex_device_id');
      final storedDeviceKey = await _storage.read(key: 'recodex_device_key');
      if (storedDeviceId != null && storedDeviceId.isNotEmpty) {
        deviceId.value = storedDeviceId;
      } else {
        await _storage.write(key: 'recodex_device_id', value: deviceId.value);
      }
      if (storedDeviceKey != null && storedDeviceKey.isNotEmpty) {
        deviceKey.value = storedDeviceKey;
      }
    } catch (_) {
      // Tests and unsupported desktop targets may not have a secure storage backend.
    }
  }

  Future<void> _storeCredentials() async {
    try {
      await _storage.write(key: 'recodex_device_id', value: deviceId.value);
      await _storage.write(key: 'recodex_device_key', value: deviceKey.value);
    } catch (_) {
      // Keep the in-memory key for the current connection if secure storage is unavailable.
    }
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
