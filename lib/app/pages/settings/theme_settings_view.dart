import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';
import 'theme_controller.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ThemeController>();
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '主题设置'),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
                children: [
                  _ThemePreview(
                    preference: controller.preference.value,
                    accent: controller.accent.value,
                  ),
                  const SizedBox(height: 24),
                  const _ThemeSectionTitle(
                    title: '界面模式',
                    subtitle: '控制系统使用浅色、深色或自动外观',
                  ),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.66,
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
                    subtitle: '强调色会同步影响图标、按钮和背景氛围',
                  ),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.66,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < RecodexThemeAccent.values.length;
                          index += 1
                        ) ...[
                          _ThemeAccentRow(
                            accent: RecodexThemeAccent.values[index],
                            selected:
                                controller.accent.value ==
                                RecodexThemeAccent.values[index],
                            onTap: () => controller.setAccent(
                              RecodexThemeAccent.values[index],
                            ),
                          ),
                          if (index != RecodexThemeAccent.values.length - 1)
                            const _ThemeDivider(),
                        ],
                      ],
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

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.preference, required this.accent});

  final RecodexThemePreference preference;
  final RecodexThemeAccent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 26,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.icon.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.icon.withValues(alpha: 0.20)),
              ),
              child: Icon(RecodexIcons.palette, color: colors.icon, size: 25),
            ),
          ),
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
                  '${preference.label} · ${accent.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    for (final option in RecodexThemeAccent.values) ...[
                      _AccentDot(
                        color: option.primary,
                        selected: option == accent,
                      ),
                      if (option != RecodexThemeAccent.values.last)
                        const SizedBox(width: 7),
                    ],
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
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
    final isDark = preference == RecodexThemePreference.dark;
    final icon = switch (preference) {
      RecodexThemePreference.system => RecodexIcons.devices,
      RecodexThemePreference.light => RecodexIcons.sun,
      RecodexThemePreference.dark => RecodexIcons.darkMode,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff182132) : const Color(0xfff5f8ff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xff39475c)
              : colors.icon.withValues(alpha: 0.18),
        ),
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(
          icon,
          color: isDark ? const Color(0xffa9c8ff) : colors.icon,
          size: 19,
        ),
      ),
    );
  }
}

class _ThemeAccentRow extends StatelessWidget {
  const _ThemeAccentRow({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final RecodexThemeAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ThemeOptionRow(
      title: accent.label,
      subtitle: accent.description,
      selected: selected,
      onTap: onTap,
      leading: SizedBox.square(
        dimension: 40,
        child: Center(
          child: _AccentDot(
            color: accent.primary,
            selected: selected,
            size: 22,
          ),
        ),
      ),
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
                        fontWeight: FontWeight.w800,
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
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

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    this.size = 16,
  });

  final Color color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? context.recodexColors.text
              : color.withValues(alpha: 0.34),
          width: selected ? 2 : 1,
        ),
      ),
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
