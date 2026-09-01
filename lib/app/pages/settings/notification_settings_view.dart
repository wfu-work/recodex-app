import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../services/task_notification_controller.dart';
import '../../theme/recodex_theme.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TaskNotificationController>();
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '消息通知'),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
                children: [
                  _NotificationHero(controller: controller),
                  const SizedBox(height: 24),
                  const _NotificationSectionTitle(
                    title: '通知类型',
                    subtitle: '选择哪些状态变化需要提醒你',
                  ),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.66,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _NotificationToggleRow(
                          icon: RecodexIcons.checkCircle,
                          title: '任务完成',
                          subtitle: 'Codex 正常完成一项任务',
                          value: controller.eventEnabled(
                            TaskNotificationEvent.completed,
                          ),
                          onChanged: (value) => controller.setEventEnabled(
                            TaskNotificationEvent.completed,
                            value,
                          ),
                        ),
                        const _NotificationDivider(),
                        _NotificationToggleRow(
                          icon: RecodexIcons.error,
                          title: '任务失败',
                          subtitle: '任务执行异常或远程命令失败',
                          value: controller.eventEnabled(
                            TaskNotificationEvent.failed,
                          ),
                          onChanged: (value) => controller.setEventEnabled(
                            TaskNotificationEvent.failed,
                            value,
                          ),
                        ),
                        const _NotificationDivider(),
                        _NotificationToggleRow(
                          icon: RecodexIcons.pause,
                          title: '任务中断',
                          subtitle: '你主动停止正在执行的任务',
                          value: controller.eventEnabled(
                            TaskNotificationEvent.interrupted,
                          ),
                          onChanged: (value) => controller.setEventEnabled(
                            TaskNotificationEvent.interrupted,
                            value,
                          ),
                        ),
                        const _NotificationDivider(),
                        _NotificationToggleRow(
                          icon: RecodexIcons.cloudOff,
                          title: '中继服务断开',
                          subtitle: 'Relay 连接意外中断时提醒',
                          value: controller.eventEnabled(
                            TaskNotificationEvent.relayDisconnected,
                          ),
                          onChanged: (value) => controller.setEventEnabled(
                            TaskNotificationEvent.relayDisconnected,
                            value,
                          ),
                        ),
                        const _NotificationDivider(),
                        _NotificationToggleRow(
                          icon: RecodexIcons.cloudDone,
                          title: '中继服务恢复',
                          subtitle: 'Relay 自动重连成功时提醒',
                          value: controller.eventEnabled(
                            TaskNotificationEvent.relayReconnected,
                          ),
                          onChanged: (value) => controller.setEventEnabled(
                            TaskNotificationEvent.relayReconnected,
                            value,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _NotificationSectionTitle(
                    title: '投递方式',
                    subtitle: '控制应用在不同系统状态下如何提醒',
                  ),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.66,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _NotificationToggleRow(
                          icon: RecodexIcons.notificationsActive,
                          title: '后台任务通知',
                          subtitle: '应用进入后台后仍投递任务状态',
                          value: controller.backgroundEnabled.value,
                          onChanged: controller.setBackgroundEnabled,
                        ),
                        const _NotificationDivider(),
                        _NotificationToggleRow(
                          icon: RecodexIcons.visibility,
                          title: '锁屏显示',
                          subtitle: '允许在锁屏通知中显示任务内容',
                          value: controller.lockScreenEnabled.value,
                          onChanged: controller.setLockScreenEnabled,
                        ),
                        const _NotificationDivider(),
                        _NotificationToggleRow(
                          icon: RecodexIcons.notifications,
                          title: '声音提示',
                          subtitle: '通知到达时播放系统提示音',
                          value: controller.soundEnabled.value,
                          onChanged: controller.setSoundEnabled,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _NotificationSectionTitle(
                    title: '权限与测试',
                    subtitle: '检查系统权限并发送一条测试通知',
                  ),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.66,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _NotificationActionRow(
                          icon: controller.permissionGranted.value
                              ? RecodexIcons.verified
                              : RecodexIcons.warning,
                          title: '系统通知权限',
                          subtitle: controller.permissionGranted.value
                              ? '已授权'
                              : '未授权，开启后才能收到提醒',
                          actionLabel: controller.permissionGranted.value
                              ? '重新检查'
                              : '请求权限',
                          onTap: controller.requestPermissions,
                        ),
                        const _NotificationDivider(),
                        _NotificationActionRow(
                          icon: RecodexIcons.notificationsActive,
                          title: '发送测试通知',
                          subtitle:
                              controller.enabled.value &&
                                  controller.permissionGranted.value
                              ? '验证当前设备的通知投递'
                              : '先开启消息通知并授予系统权限',
                          actionLabel:
                              controller.enabled.value &&
                                  controller.permissionGranted.value
                              ? '发送'
                              : '先开启',
                          onTap:
                              controller.enabled.value &&
                                  controller.permissionGranted.value
                              ? controller.sendTestNotification
                              : controller.requestPermissions,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '后台投递依赖系统允许应用保持网络活动；锁屏显示也会受到系统通知设置和专注模式影响。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.recodexColors.textMuted,
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationHero extends StatelessWidget {
  const _NotificationHero({required this.controller});

  final TaskNotificationController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final active =
        controller.enabled.value && controller.permissionGranted.value;
    return LiquidGlass(
      radius: 28,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
      child: Row(
        children: [
          Icon(
            active
                ? RecodexIcons.notificationsActive
                : RecodexIcons.notifications,
            color: active ? colors.success : colors.icon,
            size: 29,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '消息通知',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  controller.statusLabel,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: controller.enabled.value,
            onChanged: controller.setEnabled,
          ),
        ],
      ),
    );
  }
}

class _NotificationSectionTitle extends StatelessWidget {
  const _NotificationSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textMuted.withValues(alpha: 0.72),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationToggleRow extends StatelessWidget {
  const _NotificationToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      child: Row(
        children: [
          Icon(icon, color: colors.icon, size: 22),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NotificationActionRow extends StatelessWidget {
  const _NotificationActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
          child: Row(
            children: [
              Icon(icon, color: colors.icon, size: 22),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onTap, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationDivider extends StatelessWidget {
  const _NotificationDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 54,
      color: context.recodexColors.textMuted.withValues(alpha: 0.14),
    );
  }
}
