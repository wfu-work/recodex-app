import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../routes/app_pages.dart';

enum TaskNotificationStatus { completed, failed, interrupted }

enum TaskNotificationEvent {
  completed,
  failed,
  interrupted,
  relayDisconnected,
  relayReconnected,
}

class TaskNotificationController extends GetxController
    with WidgetsBindingObserver {
  TaskNotificationController({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'recodex_notifications_enabled';
  static const _preferencesStorageKey = 'recodex_notifications_preferences_v2';
  static const _channelId = 'recodex_tasks';
  static const _silentChannelId = 'recodex_tasks_silent';
  static const _channelName = 'Recodex tasks';
  static const _silentChannelName = 'Recodex tasks (silent)';
  static const _channelDescription = 'Task completion alerts from Recodex.';

  final FlutterLocalNotificationsPlugin _plugin;
  final enabled = false.obs;
  final permissionGranted = false.obs;
  final ready = false.obs;
  final completedEnabled = true.obs;
  final failedEnabled = true.obs;
  final interruptedEnabled = false.obs;
  final relayDisconnectedEnabled = true.obs;
  final relayReconnectedEnabled = false.obs;
  final backgroundEnabled = true.obs;
  final lockScreenEnabled = true.obs;
  final soundEnabled = true.obs;
  int _notificationId = 1000;
  Future<void>? _initialization;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  String get statusLabel {
    if (!enabled.value) return '已关闭';
    if (!permissionGranted.value) return '未授权';
    final count = [
      completedEnabled.value,
      failedEnabled.value,
      interruptedEnabled.value,
      relayDisconnectedEnabled.value,
      relayReconnectedEnabled.value,
    ].where((value) => value).length;
    return '已开启 · $count 类提醒';
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  Future<void> initialize() {
    if (ready.value) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
      defaultPresentSound: true,
    );
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
          macOS: darwinSettings,
        ),
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );
    } catch (_) {
      permissionGranted.value = false;
      enabled.value = false;
      return;
    }
    ready.value = true;

    await _loadPreferences();
    if (enabled.value) {
      permissionGranted.value = await _safeRequestPermissions();
      if (!permissionGranted.value) {
        enabled.value = false;
        await _persistPreferences();
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!value) {
      enabled.value = false;
      await _persistPreferences();
      return;
    }
    await initialize();
    if (!ready.value) return;

    final granted = await _safeRequestPermissions();
    permissionGranted.value = granted;
    enabled.value = granted;
    await _persistPreferences();
  }

  bool eventEnabled(TaskNotificationEvent event) {
    return switch (event) {
      TaskNotificationEvent.completed => completedEnabled.value,
      TaskNotificationEvent.failed => failedEnabled.value,
      TaskNotificationEvent.interrupted => interruptedEnabled.value,
      TaskNotificationEvent.relayDisconnected => relayDisconnectedEnabled.value,
      TaskNotificationEvent.relayReconnected => relayReconnectedEnabled.value,
    };
  }

  Future<void> setEventEnabled(TaskNotificationEvent event, bool value) async {
    switch (event) {
      case TaskNotificationEvent.completed:
        completedEnabled.value = value;
      case TaskNotificationEvent.failed:
        failedEnabled.value = value;
      case TaskNotificationEvent.interrupted:
        interruptedEnabled.value = value;
      case TaskNotificationEvent.relayDisconnected:
        relayDisconnectedEnabled.value = value;
      case TaskNotificationEvent.relayReconnected:
        relayReconnectedEnabled.value = value;
    }
    await _persistPreferences();
  }

  Future<void> setBackgroundEnabled(bool value) async {
    backgroundEnabled.value = value;
    await _persistPreferences();
  }

  Future<void> setLockScreenEnabled(bool value) async {
    lockScreenEnabled.value = value;
    await _persistPreferences();
  }

  Future<void> setSoundEnabled(bool value) async {
    soundEnabled.value = value;
    await _persistPreferences();
  }

  Future<bool> requestPermissions() async {
    await initialize();
    if (!ready.value) return false;
    permissionGranted.value = await _safeRequestPermissions();
    if (permissionGranted.value) {
      enabled.value = true;
      await _persistPreferences();
    }
    return permissionGranted.value;
  }

  Future<void> notifySessionTerminal({
    required TaskNotificationStatus status,
    required String? sessionId,
    required String workspaceName,
    required String prompt,
    String? errorMessage,
  }) async {
    final title = switch (status) {
      TaskNotificationStatus.completed => '任务已完成',
      TaskNotificationStatus.failed => '任务失败',
      TaskNotificationStatus.interrupted => '任务已中断',
    };
    final body = _notificationBody(
      status: status,
      workspaceName: workspaceName,
      prompt: prompt,
      errorMessage: errorMessage,
    );
    await _showNotification(
      event: _eventForStatus(status),
      title: title,
      body: body,
      payload: jsonEncode({
        'sessionId': sessionId ?? '',
        'workspace': workspaceName,
        'status': status.name,
      }),
    );
  }

  Future<void> notifyRelayDisconnected({String? reason}) async {
    await _showNotification(
      event: TaskNotificationEvent.relayDisconnected,
      title: 'Relay 连接已断开',
      body: reason?.trim().isNotEmpty == true
          ? reason!.trim()
          : '中继服务连接已断开，手机端将自动重试。',
      payload: jsonEncode({'status': 'relay_disconnected'}),
    );
  }

  Future<void> notifyRelayReconnected() async {
    await _showNotification(
      event: TaskNotificationEvent.relayReconnected,
      title: 'Relay 已恢复连接',
      body: '中继服务连接已恢复，可以继续操作远程 Codex。',
      payload: jsonEncode({'status': 'relay_reconnected'}),
    );
  }

  Future<void> sendTestNotification() async {
    await _showNotification(
      event: TaskNotificationEvent.completed,
      title: '通知测试成功',
      body: 'Recodex 已成功发送一条本地通知。',
      payload: jsonEncode({'status': 'test'}),
      force: true,
    );
  }

  Future<void> _showNotification({
    required TaskNotificationEvent event,
    required String title,
    required String body,
    required String payload,
    bool force = false,
  }) async {
    await initialize();
    if (!enabled.value || !permissionGranted.value) return;
    if (!force && !eventEnabled(event)) return;
    if (!force &&
        _lifecycle != AppLifecycleState.resumed &&
        !backgroundEnabled.value) {
      return;
    }

    try {
      await _plugin.show(
        id: _notificationId++,
        title: title,
        body: body,
        notificationDetails: _notificationDetails(),
        payload: payload,
      );
    } catch (_) {
      permissionGranted.value = false;
    }
  }

  NotificationDetails _notificationDetails() {
    final channelId = soundEnabled.value ? _channelId : _silentChannelId;
    final channelName = soundEnabled.value ? _channelName : _silentChannelName;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        playSound: soundEnabled.value,
        visibility: lockScreenEnabled.value
            ? NotificationVisibility.public
            : NotificationVisibility.secret,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: lockScreenEnabled.value,
        presentBanner: lockScreenEnabled.value,
        presentList: lockScreenEnabled.value,
        presentSound: soundEnabled.value,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: lockScreenEnabled.value,
        presentBanner: lockScreenEnabled.value,
        presentList: lockScreenEnabled.value,
        presentSound: soundEnabled.value,
      ),
    );
  }

  TaskNotificationEvent _eventForStatus(TaskNotificationStatus status) {
    return switch (status) {
      TaskNotificationStatus.completed => TaskNotificationEvent.completed,
      TaskNotificationStatus.failed => TaskNotificationEvent.failed,
      TaskNotificationStatus.interrupted => TaskNotificationEvent.interrupted,
    };
  }

  Future<void> _loadPreferences() async {
    try {
      final encoded = await _storage.read(key: _preferencesStorageKey);
      if (encoded != null && encoded.isNotEmpty) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          final values = Map<String, dynamic>.from(decoded);
          enabled.value = values['enabled'] == true;
          completedEnabled.value = values['completed'] != false;
          failedEnabled.value = values['failed'] != false;
          interruptedEnabled.value = values['interrupted'] == true;
          relayDisconnectedEnabled.value = values['relayDisconnected'] != false;
          relayReconnectedEnabled.value = values['relayReconnected'] == true;
          backgroundEnabled.value = values['background'] != false;
          lockScreenEnabled.value = values['lockScreen'] != false;
          soundEnabled.value = values['sound'] != false;
          return;
        }
      }
      // Migrate the original global switch while keeping the new defaults.
      enabled.value = await _storage.read(key: _storageKey) == 'true';
    } catch (_) {
      enabled.value = false;
    }
  }

  Future<void> _persistPreferences() async {
    final preferences = jsonEncode({
      'enabled': enabled.value,
      'completed': completedEnabled.value,
      'failed': failedEnabled.value,
      'interrupted': interruptedEnabled.value,
      'relayDisconnected': relayDisconnectedEnabled.value,
      'relayReconnected': relayReconnectedEnabled.value,
      'background': backgroundEnabled.value,
      'lockScreen': lockScreenEnabled.value,
      'sound': soundEnabled.value,
    });
    try {
      await _storage.write(key: _preferencesStorageKey, value: preferences);
      await _storage.write(key: _storageKey, value: enabled.value.toString());
    } catch (_) {
      // Keep in-memory preferences when secure storage is unavailable.
    }
  }

  Future<bool> _requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted =
        await android?.requestNotificationsPermission() ?? true;

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosGranted =
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;

    final macOS = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final macOSGranted =
        await macOS?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;

    return androidGranted && iosGranted && macOSGranted;
  }

  Future<bool> _safeRequestPermissions() async {
    try {
      return await _requestPermissions();
    } catch (_) {
      return false;
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    Get.offAllNamed(Routes.main);
  }

  String _notificationBody({
    required TaskNotificationStatus status,
    required String workspaceName,
    required String prompt,
    String? errorMessage,
  }) {
    final workspace = workspaceName.trim().isEmpty ? '当前工作区' : workspaceName;
    if (status == TaskNotificationStatus.failed) {
      final message = errorMessage?.trim() ?? '';
      return message.isEmpty ? '$workspace 的任务执行失败。' : message;
    }
    if (status == TaskNotificationStatus.interrupted) {
      return '$workspace 的任务已停止。';
    }
    final shortPrompt = _shorten(prompt, fallback: 'Codex 已完成回答。');
    return '$workspace · $shortPrompt';
  }

  String _shorten(String value, {required String fallback}) {
    final oneLine = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (oneLine.isEmpty) return fallback;
    return oneLine.length <= 48 ? oneLine : '${oneLine.substring(0, 48)}...';
  }
}
