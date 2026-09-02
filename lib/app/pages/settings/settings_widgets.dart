import 'package:flutter/material.dart';

import '../../theme/recodex_theme.dart';

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

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
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

/// Keeps secondary settings pages fluid without letting them become unwieldy
/// on very wide desktop windows.
class SettingsPageContent extends StatelessWidget {
  const SettingsPageContent({required this.child, super.key});

  static const maxWidth = 1440.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// The settings surface used by Codex: a quiet, opaque panel with a thin
/// border and a restrained 15px corner radius. Keeping this in one place
/// prevents each settings route from drifting into a different card style.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 15,
    this.opacity = 1,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double opacity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        // Keep the card edge present but quiet so the surface, not its
        // outline, carries the visual hierarchy of the settings page.
        color: colors.glassBorder.withValues(alpha: isDark ? 0.72 : 0.68),
        width: isDark ? 0.8 : 1,
      ),
    );
    final content = Padding(padding: padding, child: child);
    return Material(
      color: colors.glassColor.withValues(alpha: opacity),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Icon(icon, color: colors.icon, size: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 15.5,
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
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (showChevron)
            Icon(RecodexIcons.chevronRight, color: colors.textMuted),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 53,
      color: context.recodexColors.textMuted.withValues(alpha: 0.16),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: CodexSwitch(value: value, onChanged: onChanged),
    );
  }
}

/// A compact switch treatment used by every settings row.
///
/// The native switch remains in the tree for platform semantics and input
/// handling, while the visible layer uses Codex's quieter 12px track radius.
/// Keeping the 52x40 canvas preserves the comfortable settings-row hit area.
class CodexSwitch extends StatelessWidget {
  const CodexSwitch({required this.value, required this.onChanged, super.key});

  static const _trackWidth = 52.0;
  static const _trackHeight = 28.0;
  static const _trackRadius = 12.0;
  static const _thumbSize = 22.0;
  static const _thumbInset = 4.0;

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final enabled = onChanged != null;
    final trackColor = value
        ? RecodexTheme.codexBlue
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5);
    final thumbColor = value ? const Color(0xffffffff) : colors.textMuted;

    return SizedBox(
      width: 52,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedContainer(
              key: const ValueKey('codex-switch-track'),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: _trackWidth,
              height: _trackHeight,
              padding: const EdgeInsets.symmetric(horizontal: _thumbInset),
              decoration: BoxDecoration(
                color: trackColor.withValues(alpha: enabled ? 1 : 0.5),
                borderRadius: BorderRadius.circular(_trackRadius),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    color: thumbColor.withValues(alpha: enabled ? 1 : 0.5),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: enabled ? 0.12 : 0.06,
                        ),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Keep the framework's semantics, keyboard behavior, and drag
          // handling. Opacity hides only its painted layer; it still receives
          // input above the custom visual.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }
}
