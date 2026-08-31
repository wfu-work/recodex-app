import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

/// Preferences that affect how Recodex connects and starts Codex tasks.
///
/// They are deliberately kept separate from a pairing profile: changing a
/// task preference must never rewrite Relay credentials.
class SettingsPreferencesController extends GetxController {
  static const _storage = FlutterSecureStorage();

  static const _autoConnectKey = 'recodex_pref_auto_connect';
  static const _autoReconnectKey = 'recodex_pref_auto_reconnect';
  static const _showReasoningKey = 'recodex_pref_show_reasoning';
  static const _confirmActionsKey = 'recodex_pref_confirm_actions';
  static const _compactTimelineKey = 'recodex_pref_compact_timeline';
  static const _defaultModelKey = 'recodex_pref_default_model';
  static const _defaultReasoningKey = 'recodex_pref_default_reasoning';
  static const _defaultPermissionKey = 'recodex_pref_default_permission';
  static const _defaultWorkspaceKey = 'recodex_pref_default_workspace';

  final autoConnect = true.obs;
  final autoReconnect = true.obs;
  final showReasoning = true.obs;
  final confirmSensitiveActions = true.obs;
  final compactTimeline = false.obs;
  final defaultModel = '自动选择'.obs;
  final defaultReasoningEffort = 'medium'.obs;
  final defaultPermissionMode = '默认权限'.obs;
  final defaultWorkspacePath = ''.obs;

  final _loaded = Completer<void>();

  Future<void> get ready => _loaded.future;

  @override
  void onInit() {
    super.onInit();
    unawaited(_load());
  }

  void setAutoConnect(bool value) {
    autoConnect.value = value;
    unawaited(_writeBool(_autoConnectKey, value));
  }

  void setAutoReconnect(bool value) {
    autoReconnect.value = value;
    unawaited(_writeBool(_autoReconnectKey, value));
  }

  void setShowReasoning(bool value) {
    showReasoning.value = value;
    unawaited(_writeBool(_showReasoningKey, value));
  }

  void setConfirmSensitiveActions(bool value) {
    confirmSensitiveActions.value = value;
    unawaited(_writeBool(_confirmActionsKey, value));
  }

  void setCompactTimeline(bool value) {
    compactTimeline.value = value;
    unawaited(_writeBool(_compactTimelineKey, value));
  }

  void setDefaultModel(String value) {
    defaultModel.value = value;
    unawaited(_write(_defaultModelKey, value));
  }

  void setDefaultReasoningEffort(String value) {
    defaultReasoningEffort.value = value;
    unawaited(_write(_defaultReasoningKey, value));
  }

  void setDefaultPermissionMode(String value) {
    defaultPermissionMode.value = value;
    unawaited(_write(_defaultPermissionKey, value));
  }

  void setDefaultWorkspacePath(String value) {
    defaultWorkspacePath.value = value;
    unawaited(_write(_defaultWorkspaceKey, value));
  }

  Future<void> resetTaskPreferences() async {
    autoConnect.value = true;
    autoReconnect.value = true;
    showReasoning.value = true;
    confirmSensitiveActions.value = true;
    compactTimeline.value = false;
    defaultModel.value = '自动选择';
    defaultReasoningEffort.value = 'medium';
    defaultPermissionMode.value = '默认权限';
    defaultWorkspacePath.value = '';
    try {
      await Future.wait([
        _storage.delete(key: _autoConnectKey),
        _storage.delete(key: _autoReconnectKey),
        _storage.delete(key: _showReasoningKey),
        _storage.delete(key: _confirmActionsKey),
        _storage.delete(key: _compactTimelineKey),
        _storage.delete(key: _defaultModelKey),
        _storage.delete(key: _defaultReasoningKey),
        _storage.delete(key: _defaultPermissionKey),
        _storage.delete(key: _defaultWorkspaceKey),
      ]);
    } catch (_) {
      // Keep the reset values in memory when secure storage is unavailable.
    }
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _autoConnectKey),
        _storage.read(key: _autoReconnectKey),
        _storage.read(key: _showReasoningKey),
        _storage.read(key: _confirmActionsKey),
        _storage.read(key: _compactTimelineKey),
        _storage.read(key: _defaultModelKey),
        _storage.read(key: _defaultReasoningKey),
        _storage.read(key: _defaultPermissionKey),
        _storage.read(key: _defaultWorkspaceKey),
      ]);
      autoConnect.value = _readBool(values[0], fallback: true);
      autoReconnect.value = _readBool(values[1], fallback: true);
      showReasoning.value = _readBool(values[2], fallback: true);
      confirmSensitiveActions.value = _readBool(values[3], fallback: true);
      compactTimeline.value = _readBool(values[4], fallback: false);
      defaultModel.value = _readString(values[5], fallback: '自动选择');
      defaultReasoningEffort.value = _readString(values[6], fallback: 'medium');
      defaultPermissionMode.value = _readString(values[7], fallback: '默认权限');
      defaultWorkspacePath.value = _readString(values[8], fallback: '');
    } catch (_) {
      // Defaults remain usable when secure storage is unavailable (for example
      // in a widget test or an unsupported desktop target).
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> _writeBool(String key, bool value) => _write(key, '$value');

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Keep the in-memory preference when secure storage is unavailable.
    }
  }

  static bool _readBool(String? value, {required bool fallback}) {
    if (value == null) return fallback;
    return value.toLowerCase() == 'true';
  }

  static String _readString(String? value, {required String fallback}) {
    final next = value?.trim() ?? '';
    return next.isEmpty ? fallback : next;
  }
}
