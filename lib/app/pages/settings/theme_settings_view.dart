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
                  _ThemePreview(preference: controller.preference.value),
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
                    subtitle: '统一使用黑白中性色，保持 Codex 风格',
                  ),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.66,
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
  const _ThemePreview({required this.preference});

  final RecodexThemePreference preference;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 26,
      opacity: 0.72,
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
                    fontWeight: FontWeight.w800,
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
    final icon = switch (preference) {
      RecodexThemePreference.system => RecodexIcons.devices,
      RecodexThemePreference.light => RecodexIcons.sun,
      RecodexThemePreference.dark => RecodexIcons.darkMode,
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
            fontWeight: FontWeight.w700,
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
