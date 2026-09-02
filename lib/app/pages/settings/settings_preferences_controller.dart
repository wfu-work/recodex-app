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
  static const _shortcutsEnabledKey = 'recodex_pref_shortcuts_enabled';
  static const _collapseReasoningKey =
      'recodex_pref_collapse_reasoning_by_default';
  static const _showConversationIndexKey =
      'recodex_pref_show_conversation_index';
  static const _autoScrollToLatestKey = 'recodex_pref_auto_scroll_latest';
  static const _showToolCallDetailsKey = 'recodex_pref_show_tool_details';
  static const _showUsageMetricsKey = 'recodex_pref_show_usage_metrics';
  static const _answerMaxWidthKey = 'recodex_pref_answer_max_width';
  static const _answerHorizontalPaddingKey =
      'recodex_pref_answer_horizontal_padding';
  static const _compactSidebarKey = 'recodex_pref_compact_sidebar';
  static const _showTopTitleBarKey = 'recodex_pref_show_top_title_bar';
  static const _showIndexHoverPreviewKey =
      'recodex_pref_show_index_hover_preview';
  static const _reduceAnimationsKey = 'recodex_pref_reduce_animations';
  static const _answerCardRadiusKey = 'recodex_pref_answer_card_radius';

  final autoConnect = true.obs;
  final autoReconnect = true.obs;
  final showReasoning = true.obs;
  final confirmSensitiveActions = true.obs;
  final compactTimeline = false.obs;
  final defaultModel = '自动选择'.obs;
  final defaultReasoningEffort = 'medium'.obs;
  final defaultPermissionMode = '默认权限'.obs;
  final defaultWorkspacePath = ''.obs;
  final shortcutsEnabled = true.obs;
  final collapseReasoningByDefault = true.obs;
  final showConversationIndex = true.obs;
  final autoScrollToLatest = true.obs;
  final showToolCallDetails = true.obs;
  final showUsageMetrics = true.obs;
  final answerMaxWidth = 960.0.obs;
  final answerHorizontalPadding = 16.0.obs;
  final compactSidebar = false.obs;
  final showTopTitleBar = true.obs;
  final showIndexHoverPreview = true.obs;
  final reduceAnimations = false.obs;

  /// Radius used by conversation message and result cards.
  ///
  /// Keep this as a numeric preference so the setting can be shared by all
  /// transcript surfaces without coupling the widgets to a particular option
  /// label. The value is clamped when loaded and when changed.
  final answerCardRadius = 24.0.obs;

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

  void setShortcutsEnabled(bool value) {
    shortcutsEnabled.value = value;
    unawaited(_writeBool(_shortcutsEnabledKey, value));
  }

  void setCollapseReasoningByDefault(bool value) {
    collapseReasoningByDefault.value = value;
    unawaited(_writeBool(_collapseReasoningKey, value));
  }

  void setShowConversationIndex(bool value) {
    showConversationIndex.value = value;
    unawaited(_writeBool(_showConversationIndexKey, value));
  }

  void setAutoScrollToLatest(bool value) {
    autoScrollToLatest.value = value;
    unawaited(_writeBool(_autoScrollToLatestKey, value));
  }

  void setShowToolCallDetails(bool value) {
    showToolCallDetails.value = value;
    unawaited(_writeBool(_showToolCallDetailsKey, value));
  }

  void setShowUsageMetrics(bool value) {
    showUsageMetrics.value = value;
    unawaited(_writeBool(_showUsageMetricsKey, value));
  }

  void setAnswerMaxWidth(double value) {
    final normalized = value.clamp(560.0, 1200.0).toDouble();
    answerMaxWidth.value = normalized;
    unawaited(_write(_answerMaxWidthKey, '$normalized'));
  }

  void setAnswerHorizontalPadding(double value) {
    final normalized = value.clamp(8.0, 40.0).toDouble();
    answerHorizontalPadding.value = normalized;
    unawaited(_write(_answerHorizontalPaddingKey, '$normalized'));
  }

  void setCompactSidebar(bool value) {
    compactSidebar.value = value;
    unawaited(_writeBool(_compactSidebarKey, value));
  }

  void setShowTopTitleBar(bool value) {
    showTopTitleBar.value = value;
    unawaited(_writeBool(_showTopTitleBarKey, value));
  }

  void setShowIndexHoverPreview(bool value) {
    showIndexHoverPreview.value = value;
    unawaited(_writeBool(_showIndexHoverPreviewKey, value));
  }

  void setReduceAnimations(bool value) {
    reduceAnimations.value = value;
    unawaited(_writeBool(_reduceAnimationsKey, value));
  }

  void setAnswerCardRadius(double value) {
    final normalized = value.clamp(10.0, 32.0).toDouble();
    answerCardRadius.value = normalized;
    unawaited(_write(_answerCardRadiusKey, '$normalized'));
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
    shortcutsEnabled.value = true;
    collapseReasoningByDefault.value = true;
    showConversationIndex.value = true;
    autoScrollToLatest.value = true;
    showToolCallDetails.value = true;
    showUsageMetrics.value = true;
    answerMaxWidth.value = 960;
    answerHorizontalPadding.value = 16;
    compactSidebar.value = false;
    showTopTitleBar.value = true;
    showIndexHoverPreview.value = true;
    reduceAnimations.value = false;
    answerCardRadius.value = 24;
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
        _storage.delete(key: _shortcutsEnabledKey),
        _storage.delete(key: _collapseReasoningKey),
        _storage.delete(key: _showConversationIndexKey),
        _storage.delete(key: _autoScrollToLatestKey),
        _storage.delete(key: _showToolCallDetailsKey),
        _storage.delete(key: _showUsageMetricsKey),
        _storage.delete(key: _answerMaxWidthKey),
        _storage.delete(key: _answerHorizontalPaddingKey),
        _storage.delete(key: _compactSidebarKey),
        _storage.delete(key: _showTopTitleBarKey),
        _storage.delete(key: _showIndexHoverPreviewKey),
        _storage.delete(key: _reduceAnimationsKey),
        _storage.delete(key: _answerCardRadiusKey),
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
        _storage.read(key: _shortcutsEnabledKey),
        _storage.read(key: _collapseReasoningKey),
        _storage.read(key: _showConversationIndexKey),
        _storage.read(key: _autoScrollToLatestKey),
        _storage.read(key: _showToolCallDetailsKey),
        _storage.read(key: _showUsageMetricsKey),
        _storage.read(key: _answerMaxWidthKey),
        _storage.read(key: _answerHorizontalPaddingKey),
        _storage.read(key: _compactSidebarKey),
        _storage.read(key: _showTopTitleBarKey),
        _storage.read(key: _showIndexHoverPreviewKey),
        _storage.read(key: _reduceAnimationsKey),
        _storage.read(key: _answerCardRadiusKey),
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
      shortcutsEnabled.value = _readBool(values[9], fallback: true);
      collapseReasoningByDefault.value = _readBool(values[10], fallback: true);
      showConversationIndex.value = _readBool(values[11], fallback: true);
      autoScrollToLatest.value = _readBool(values[12], fallback: true);
      showToolCallDetails.value = _readBool(values[13], fallback: true);
      showUsageMetrics.value = _readBool(values[14], fallback: true);
      answerMaxWidth.value = _readDouble(
        values[15],
        fallback: 960,
      ).clamp(560.0, 1200.0).toDouble();
      answerHorizontalPadding.value = _readDouble(
        values[16],
        fallback: 16,
      ).clamp(8.0, 40.0).toDouble();
      compactSidebar.value = _readBool(values[17], fallback: false);
      showTopTitleBar.value = _readBool(values[18], fallback: true);
      showIndexHoverPreview.value = _readBool(values[19], fallback: true);
      reduceAnimations.value = _readBool(values[20], fallback: false);
      answerCardRadius.value = _readDouble(
        values[21],
        fallback: 24,
      ).clamp(10.0, 32.0).toDouble();
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

  static double _readDouble(String? value, {required double fallback}) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed;
  }
}
