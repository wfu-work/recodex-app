import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';
import 'settings_preferences_controller.dart';
import 'settings_widgets.dart';

class ShortcutsSettingsPage extends StatelessWidget {
  const ShortcutsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : Get.put(SettingsPreferencesController(), permanent: true);
    final primary = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘'
        : 'Ctrl';
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '桌面快捷键'),
          body: SettingsPageContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                const SettingsSectionTitle(
                  title: '快捷操作',
                  subtitle: '在 RecoDex 窗口中使用这些快捷键，可以更快地切换任务和发送消息。',
                ),
                const SizedBox(height: 12),
                SettingsGroup(
                  children: [
                    SettingsToggleRow(
                      icon: RecodexIcons.key,
                      title: '启用桌面快捷键',
                      subtitle: '关闭后不会响应下方快捷键，但输入框仍可正常使用',
                      value: preferences.shortcutsEnabled.value,
                      onChanged: preferences.setShortcutsEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const SettingsSectionTitle(
                  title: '任务与导航',
                  subtitle: '快捷键只在 RecoDex 窗口处于活动状态时生效。',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    _ShortcutRow(
                      icon: RecodexIcons.add,
                      title: '新建任务',
                      subtitle: '清空当前对话并聚焦输入框',
                      keys: [primary, 'N'],
                    ),
                    const SettingsDivider(),
                    _ShortcutRow(
                      icon: RecodexIcons.search,
                      title: '命令面板',
                      subtitle: '打开常用操作菜单',
                      keys: [primary, 'K'],
                    ),
                    const SettingsDivider(),
                    _ShortcutRow(
                      icon: RecodexIcons.menu,
                      title: '显示/隐藏侧边栏',
                      subtitle: '快速展开或收起项目和任务列表',
                      keys: [primary, 'B'],
                    ),
                    const SettingsDivider(),
                    _ShortcutRow(
                      icon: RecodexIcons.edit,
                      title: '聚焦输入框',
                      subtitle: '将光标移动到任务输入框',
                      keys: [primary, 'L'],
                    ),
                    const SettingsDivider(),
                    _ShortcutRow(
                      icon: RecodexIcons.arrowUp,
                      title: '发送消息',
                      subtitle: '提交当前输入内容',
                      keys: [primary, 'Enter'],
                    ),
                    const SettingsDivider(),
                    _ShortcutRow(
                      icon: RecodexIcons.stop,
                      title: '停止任务',
                      subtitle: '中断正在运行的 Codex 任务',
                      keys: ['Esc'],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '提示：在 macOS 上使用 Command，在 Windows/Linux 上使用 Ctrl。',
                  style: TextStyle(
                    color: context.recodexColors.textMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keys,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < keys.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  '+',
                  style: TextStyle(
                    color: context.recodexColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            _KeyCap(label: keys[index]),
          ],
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: colors.glassShadow.withValues(alpha: 0.12),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: colors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
