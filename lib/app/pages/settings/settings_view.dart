import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../routes/app_pages.dart';
import '../../services/task_notification_controller.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import 'theme_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final BridgeController controller = Get.find();
  final ThemeController themeController = Get.find();
  final TaskNotificationController notificationController = Get.find();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '设置'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 38, 24, 36),
            children: [
              _SettingsGroup(
                title: '外观',
                children: [
                  _SettingsTile(
                    icon: RecodexIcons.fontSize,
                    title: '字体大小',
                    subtitle: _fontSizeLabel,
                    trailing: SizedBox(
                      width: 148,
                      child: Slider(
                        value: themeController.fontScaleToSliderValue(),
                        min: 0,
                        max: 2,
                        divisions: 2,
                        onChanged: themeController.setFontScale,
                      ),
                    ),
                  ),
                  _DividerLine(),
                  _SettingsTile(
                    icon: RecodexIcons.darkMode,
                    title: '主题设置',
                    subtitle:
                        '${themeController.preference.value.label} · ${themeController.accent.value.label}',
                    trailingIcon: RecodexIcons.chevronRight,
                    onTap: () => _openPage(Routes.theme),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '通知',
                children: [
                  _SettingsTile(
                    icon: RecodexIcons.notifications,
                    title: '消息通知',
                    subtitle: notificationController.statusLabel,
                    trailing: Switch(
                      value: notificationController.enabled.value,
                      onChanged: notificationController.setEnabled,
                    ),
                    trailingIcon: RecodexIcons.chevronRight,
                    onTap: () => _openPage(Routes.notifications),
                  ),
                  if (notificationController.enabled.value &&
                      notificationController.permissionGranted.value) ...[
                    _DividerLine(),
                    _SettingsTile(
                      icon: RecodexIcons.notificationsActive,
                      title: '测试通知',
                      subtitle: '发送一条本地通知',
                      trailingIcon: RecodexIcons.chevronRight,
                      onTap: notificationController.sendTestNotification,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '服务',
                children: [
                  _SettingsTile(
                    icon: controller.connected.value
                        ? RecodexIcons.cloudDone
                        : RecodexIcons.cloudOff,
                    title: '服务状态',
                    subtitle: controller.connected.value
                        ? 'Bridge 在线'
                        : 'Bridge 未连接',
                    trailing: _StatusDot(connected: controller.connected.value),
                    trailingIcon: RecodexIcons.chevronRight,
                    onTap: () => _openPage(Routes.service),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '关于',
                children: [
                  _SettingsTile(
                    icon: RecodexIcons.info,
                    title: '关于我们',
                    subtitle: 'Remodex Companion',
                    trailingIcon: RecodexIcons.chevronRight,
                    onTap: () => _openPage(Routes.about),
                  ),
                  _DividerLine(),
                  const _SettingsTile(
                    icon: RecodexIcons.updates,
                    title: '检测更新',
                    subtitle: '当前版本 v1.0.4',
                    trailingText: '已是最新',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _fontSizeLabel {
    return themeController.fontSizeLabel;
  }

  void _openPage(String route) {
    Get.toNamed(route);
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        LiquidGlass(
          radius: 24,
          opacity: 0.66,
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingText,
    this.trailingIcon,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? trailingText;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
      child: Row(
        children: [
          Icon(icon, color: colors.icon, size: 23),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(
                color: colors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (trailingIcon != null) Icon(trailingIcon, color: colors.textMuted),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Icon(
      RecodexIcons.circle,
      size: 12,
      color: connected ? colors.success : colors.textMuted,
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Divider(
      height: 1,
      indent: 53,
      color: colors.textMuted.withValues(alpha: 0.16),
    );
  }
}
