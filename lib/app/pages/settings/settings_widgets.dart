import 'package:flutter/material.dart';

import '../../components/recodex_dropdown.dart';
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
    this.stackTrailing = false,
    this.onTap,
    this.showChevron = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool stackTrailing;
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
                  maxLines: stackTrailing ? 2 : 1,
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
                  maxLines: stackTrailing ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (stackTrailing && trailing != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null && !stackTrailing) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
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

/// The shared selector row for settings pages. Short values stay compact;
/// long values leave room for the title and remain readable in the popup.
class SettingsDropdownRow<T> extends StatelessWidget {
  const SettingsDropdownRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
    this.emptyLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<RecodexDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final stackTrailing = constraints.maxWidth / textScale < 300;
        final maxWidth =
            (stackTrailing
                    ? constraints.maxWidth - 65
                    : constraints.maxWidth * 0.45)
                .clamp(0.0, 220.0);
        return SettingsRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          stackTrailing: stackTrailing,
          trailing: options.isNotEmpty
              ? RecodexDropdown<T>(
                  value: value,
                  options: options,
                  onChanged: onChanged,
                  maxWidth: maxWidth,
                  compact: true,
                  tooltip: '选择$title',
                )
              : emptyLabel == null
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Text(
                    emptyLabel!,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: context.recodexColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        );
      },
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

/// Codex's 32x20 pill and 16px white thumb, with a larger touch target.
/// The framework switch handles semantics, keyboard input, and dragging.
class CodexSwitch extends StatefulWidget {
  const CodexSwitch({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<CodexSwitch> createState() => _CodexSwitchState();
}

class _CodexSwitchState extends State<CodexSwitch> {
  static const _trackWidth = 32.0;
  static const _trackHeight = 20.0;
  static const _thumbSize = 16.0;
  static const _thumbInset = 2.0;

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final switchTheme = Theme.of(context).switchTheme;
    final enabled = widget.onChanged != null;
    final states = <WidgetState>{if (widget.value) WidgetState.selected};
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedContainer(
              duration: duration,
              width: _trackWidth + 6,
              height: _trackHeight + 6,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular((_trackHeight + 6) / 2),
                border: Border.all(
                  color: enabled && _focused
                      ? RecodexTheme.codexBlue
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: AnimatedOpacity(
                opacity: enabled ? 1 : 0.6,
                duration: duration,
                child: AnimatedContainer(
                  key: const ValueKey('codex-switch-track'),
                  duration: duration,
                  curve: Curves.easeOut,
                  width: _trackWidth,
                  height: _trackHeight,
                  padding: const EdgeInsets.symmetric(horizontal: _thumbInset),
                  decoration: BoxDecoration(
                    color: switchTheme.trackColor?.resolve(states),
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                  ),
                  child: AnimatedAlign(
                    duration: duration,
                    curve: Curves.easeOut,
                    alignment: widget.value
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: switchTheme.thumbColor?.resolve(states),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 2,
                            spreadRadius: -1,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              // A fully transparent switch must still expose its state and
              // toggle action to assistive technologies.
              alwaysIncludeSemantics: true,
              child: Switch(
                value: widget.value,
                onChanged: widget.onChanged,
                onFocusChange: (focused) {
                  setState(() => _focused = focused);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
