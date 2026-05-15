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
                    icon: Icons.text_fields,
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
                  _SettingsMenuTile(
                    icon: Icons.dark_mode_outlined,
                    title: '主题设置',
                    value: themeController.preference.value.label,
                    options: RecodexThemePreference.values
                        .map((preference) => preference.label)
                        .toList(),
                    onSelected: (value) => themeController.setPreference(
                      RecodexThemePreference.fromLabel(value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '通知',
                children: [
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    title: '消息通知',
                    subtitle: notificationController.statusLabel,
                    trailing: Switch(
                      value: notificationController.enabled.value,
                      onChanged: notificationController.setEnabled,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '服务',
                children: [
                  _SettingsTile(
                    icon: controller.connected.value
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off,
                    title: '服务状态',
                    subtitle: controller.connected.value
                        ? 'Bridge 在线'
                        : 'Bridge 未连接',
                    trailing: _StatusDot(connected: controller.connected.value),
                    trailingIcon: Icons.chevron_right,
                    onTap: () => _openPage(Routes.service),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '关于',
                children: [
                  _SettingsTile(
                    icon: Icons.info_outline,
                    title: '关于我们',
                    subtitle: 'Remodex Companion',
                    trailingIcon: Icons.chevron_right,
                    onTap: () => _openPage(Routes.about),
                  ),
                  _DividerLine(),
                  const _SettingsTile(
                    icon: Icons.new_releases_outlined,
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

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: icon,
      title: title,
      subtitle: '当前：$value',
      trailingText: value,
      trailingIcon: Icons.keyboard_arrow_down,
      onTap: () => _showOptions(context),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) =>
          _SettingsOptionSheet(title: title, value: value, options: options),
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

class _SettingsOptionSheet extends StatelessWidget {
  const _SettingsOptionSheet({
    required this.title,
    required this.value,
    required this.options,
  });

  final String title;
  final String value;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: LiquidGlass(
        radius: 26,
        opacity: 0.84,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.textMuted),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < options.length; index += 1) ...[
              _SettingsOptionTile(
                label: options[index],
                selected: options[index] == value,
              ),
              if (index != options.length - 1) _DividerLine(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsOptionTile extends StatelessWidget {
  const _SettingsOptionTile({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(label),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, color: colors.icon, size: 22),
            ],
          ),
        ),
      ),
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
      Icons.circle,
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
