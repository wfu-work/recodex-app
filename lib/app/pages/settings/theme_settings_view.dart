import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../theme/recodex_theme.dart';
import 'settings_widgets.dart';
import 'settings_preferences_controller.dart';
import 'theme_controller.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ThemeController>();
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : Get.put(SettingsPreferencesController(), permanent: true);
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '主题设置'),
          body: SettingsPageContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                _ThemePreview(preference: controller.preference.value),
                const SizedBox(height: 24),
                const _ThemeSectionTitle(
                  title: '界面模式',
                  subtitle: '控制系统使用浅色、深色或自动外观',
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < RecodexThemePreference.values.length;
                        index += 1
                      ) ...[
                        _ThemeModeRow(
                          preference: RecodexThemePreference.values[index],
                          selected:
                              controller.preference.value ==
                              RecodexThemePreference.values[index],
                          onTap: () => controller.setPreference(
                            RecodexThemePreference.values[index],
                          ),
                        ),
                        if (index != RecodexThemePreference.values.length - 1)
                          const _ThemeDivider(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _ThemeSectionTitle(
                  title: '主题色',
                  subtitle: '统一使用黑白中性色，保持 Codex 风格',
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const _NeutralSwatch(
                        color: Color(0xff171717),
                        label: '黑色',
                      ),
                      const SizedBox(width: 24),
                      const _NeutralSwatch(
                        color: Color(0xfff5f5f5),
                        label: '白色',
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          '图标、按钮和文字统一使用黑白中性色',
                          style: TextStyle(
                            color: context.recodexColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _ThemeSectionTitle(
                  title: '界面细节',
                  subtitle: '调整侧边栏、标题栏、动画和可读性增强选项',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    _AppearanceSelectorRow(
                      icon: RecodexIcons.menu,
                      title: '侧边栏密度',
                      subtitle: '舒适模式留白更多，紧凑模式显示更多项目和任务',
                      value: preferences.compactSidebar.value
                          ? 'compact'
                          : 'comfortable',
                      options: const [
                        RecodexDropdownOption(
                          value: 'comfortable',
                          label: '舒适',
                        ),
                        RecodexDropdownOption(value: 'compact', label: '紧凑'),
                      ],
                      onChanged: (value) =>
                          preferences.setCompactSidebar(value == 'compact'),
                    ),
                    const SettingsDivider(),
                    _AppearanceSelectorRow(
                      icon: RecodexIcons.tune,
                      title: '对话卡片圆角',
                      subtitle: '统一调整消息、工具和文件结果卡片的圆角大小',
                      value: '${preferences.answerCardRadius.value.round()}',
                      options: const [
                        RecodexDropdownOption(value: '10', label: '小 · 10'),
                        RecodexDropdownOption(value: '18', label: '中 · 18'),
                        RecodexDropdownOption(value: '24', label: '大 · 24'),
                        RecodexDropdownOption(value: '32', label: '特大 · 32'),
                      ],
                      onChanged: (value) => preferences.setAnswerCardRadius(
                        double.tryParse(value) ?? 24,
                      ),
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.monitor,
                      title: '显示顶部标题栏',
                      subtitle: '显示当前任务名称和项目名称',
                      value: preferences.showTopTitleBar.value,
                      onChanged: preferences.setShowTopTitleBar,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.accountTree,
                      title: '显示索引悬浮提示',
                      subtitle: '鼠标悬停在对话索引短线上时显示问题预览',
                      value: preferences.showIndexHoverPreview.value,
                      onChanged: preferences.setShowIndexHoverPreview,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.pause,
                      title: '减少动画',
                      subtitle: '停用页面过渡、输入框和索引的非必要动画',
                      value: preferences.reduceAnimations.value,
                      onChanged: preferences.setReduceAnimations,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.contrast,
                      title: '高对比度模式',
                      subtitle: '提高文字、边框和背景之间的对比度',
                      value: controller.highContrast.value,
                      onChanged: controller.setHighContrast,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.preference});

  final RecodexThemePreference preference;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return SettingsCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      child: Row(
        children: [
          Icon(RecodexIcons.palette, color: colors.icon, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前外观',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${preference.label} · 黑白主题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                const Row(
                  children: [
                    _NeutralSwatch(color: Color(0xff171717), label: '黑色'),
                    SizedBox(width: 8),
                    _NeutralSwatch(color: Color(0xfff5f5f5), label: '白色'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSectionTitle extends StatelessWidget {
  const _ThemeSectionTitle({required this.title, required this.subtitle});

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
              color: colors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final RecodexThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ThemeOptionRow(
      title: preference.label,
      subtitle: preference.description,
      selected: selected,
      onTap: onTap,
      leading: _ThemeModePreview(preference: preference),
    );
  }
}

class _ThemeModePreview extends StatelessWidget {
  const _ThemeModePreview({required this.preference});

  final RecodexThemePreference preference;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final icon = switch (preference) {
      RecodexThemePreference.system => RecodexIcons.devices,
      RecodexThemePreference.light => RecodexIcons.sun,
      RecodexThemePreference.dark => RecodexIcons.darkMode,
      RecodexThemePreference.scheduled => RecodexIcons.calendar,
    };
    return SizedBox.square(
      dimension: 40,
      child: Icon(icon, color: colors.text, size: 21),
    );
  }
}

class _ThemeOptionRow extends StatelessWidget {
  const _ThemeOptionRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.leading,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? colors.icon : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.icon : colors.textMuted,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  RecodexIcons.check,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Colors.transparent,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceSelectorRow extends StatelessWidget {
  const _AppearanceSelectorRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final List<RecodexDropdownOption<String>> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.any((option) => option.value == value)
        ? value
        : options.first.value;
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 120,
        child: RecodexDropdown<String>(
          value: selected,
          options: options,
          maxWidth: 120,
          compact: true,
          tooltip: '选择$title',
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _NeutralSwatch extends StatelessWidget {
  const _NeutralSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? const Color(0xff707070) : const Color(0xffbdbdbd),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: colors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ThemeDivider extends StatelessWidget {
  const _ThemeDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 69,
      color: context.recodexColors.textMuted.withValues(alpha: 0.14),
    );
  }
}
