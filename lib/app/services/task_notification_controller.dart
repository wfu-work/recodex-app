import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../routes/app_pages.dart';

enum TaskNotificationStatus { completed, failed, interrupted }

class TaskNotificationController extends GetxController {
  TaskNotificationController({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'recodex_notifications_enabled';
  static const _channelId = 'recodex_tasks';
  static const _channelName = 'Recodex tasks';
  static const _channelDescription = 'Task completion alerts from Recodex.';

  final FlutterLocalNotificationsPlugin _plugin;
  final enabled = false.obs;
  final permissionGranted = false.obs;
  final ready = false.obs;
  int _notificationId = 1000;

  String get statusLabel {
    if (!enabled.value) return '已关闭';
    if (!permissionGranted.value) return '未授权';
    return '任务完成后提醒';
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    if (ready.value) return;
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
      ready.value = true;
      return;
    }
    ready.value = true;

    final stored = await _storage.read(key: _storageKey);
    enabled.value = stored == 'true';
    if (enabled.value) {
      permissionGranted.value = await _safeRequestPermissions();
      if (!permissionGranted.value) {
        enabled.value = false;
        await _storage.write(key: _storageKey, value: 'false');
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (!value) {
      enabled.value = false;
      await _storage.write(key: _storageKey, value: 'false');
      return;
    }

    final granted = await _safeRequestPermissions();
    permissionGranted.value = granted;
    enabled.value = granted;
    await _storage.write(key: _storageKey, value: granted ? 'true' : 'false');
  }

  Future<void> notifySessionTerminal({
    required TaskNotificationStatus status,
    required String? sessionId,
    required String workspaceName,
    required String prompt,
    String? errorMessage,
  }) async {
    await initialize();
    if (!enabled.value || !permissionGranted.value) return;

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
    final payload = jsonEncode({
      'sessionId': sessionId ?? '',
      'workspace': workspaceName,
      'status': status.name,
    });

    try {
      await _plugin.show(
        id: _notificationId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      permissionGranted.value = false;
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
    } on MissingPluginException {
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
