import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

/// A menu button that keeps popup-menu behavior in one place.
///
/// Use this for action menus as well as [RecodexDropdown]. The visual treatment
/// is supplied by [RecodexTheme], while this wrapper standardizes the trigger
/// padding and the menu positioning used throughout the app.
class RecodexPopupMenuButton<T> extends StatelessWidget {
  const RecodexPopupMenuButton({
    required this.itemBuilder,
    this.initialValue,
    this.onOpened,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.padding = EdgeInsets.zero,
    this.menuPadding,
    this.child,
    this.icon,
    this.iconSize,
    this.offset = Offset.zero,
    this.enabled = true,
    this.constraints,
    this.position,
    this.borderRadius,
    this.enableFeedback,
    super.key,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final VoidCallback? onOpened;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? menuPadding;
  final Widget? child;
  final Widget? icon;
  final double? iconSize;
  final Offset offset;
  final bool enabled;
  final BoxConstraints? constraints;
  final PopupMenuPosition? position;
  final BorderRadius? borderRadius;
  final bool? enableFeedback;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      itemBuilder: itemBuilder,
      initialValue: initialValue,
      onOpened: onOpened,
      onSelected: onSelected,
      onCanceled: onCanceled,
      tooltip: tooltip,
      padding: padding,
      menuPadding: menuPadding,
      icon: icon,
      iconSize: iconSize,
      offset: offset,
      enabled: enabled,
      constraints:
          constraints ?? const BoxConstraints(minWidth: 168, maxWidth: 280),
      position: position,
      borderRadius: borderRadius,
      enableFeedback: enableFeedback,
      child: child,
    );
  }
}

/// A compact, system-styled selector used for model, reasoning, and policy
/// choices. It intentionally uses the same popup menu as action menus so
/// keyboard, touch, and desktop pointer behavior stay consistent.
class RecodexDropdownOption<T> {
  const RecodexDropdownOption({
    required this.value,
    required this.label,
    this.leading,
    this.enabled = true,
  });

  final T value;
  final String label;
  final Widget? leading;
  final bool enabled;
}

class RecodexDropdown<T> extends StatelessWidget {
  const RecodexDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
    this.leadingIcon,
    this.tooltip,
    this.warningWhen,
    this.compact = false,
    this.maxWidth = 168,
    this.enabled = true,
    this.showCheckmark = true,
    this.showBorder = true,
    super.key,
  });

  final T value;
  final List<RecodexDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? leadingIcon;
  final String? tooltip;
  final bool Function(T value)? warningWhen;
  final bool compact;
  final double maxWidth;
  final bool enabled;
  final bool showCheckmark;
  final bool showBorder;

  RecodexDropdownOption<T>? get _selectedOption {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return options.isEmpty ? null : options.first;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    if (selected == null) return const SizedBox.shrink();

    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWarning = warningWhen?.call(selected.value) ?? false;
    final foreground = isWarning ? colors.warning : colors.textMuted;
    final radius = BorderRadius.circular(compact ? 13 : 16);
    final verticalPadding = compact ? 7.0 : 9.0;

    return RecodexPopupMenuButton<T>(
      initialValue: selected.value,
      enabled: enabled,
      tooltip: tooltip ?? '选择${selected.label}',
      constraints: BoxConstraints(minWidth: maxWidth),
      borderRadius: radius,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option.value,
            enabled: option.enabled,
            height: compact ? 44 : 48,
            child: Row(
              children: [
                if (option.leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      size: 18,
                      color: context.recodexColors.textMuted,
                    ),
                    child: option.leading!,
                  ),
                  const SizedBox(width: 10),
                ] else if (showCheckmark) ...[
                  SizedBox(
                    width: 18,
                    child: option.value == selected.value
                        ? Icon(RecodexIcons.check, size: 18, color: colors.icon)
                        : null,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Text(option.label)),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? colors.glassColor.withValues(alpha: 0.46)
              : colors.surfaceOverlay.withValues(alpha: 0.72),
          borderRadius: radius,
          border: showBorder
              ? Border.all(
                  color: isWarning
                      ? colors.warning.withValues(alpha: 0.42)
                      : colors.glassBorder.withValues(
                          alpha: isDark ? 0.84 : 0.92,
                        ),
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 13,
            vertical: verticalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: compact ? 17 : 18, color: foreground),
                SizedBox(width: compact ? 5 : 7),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Text(
                  selected.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: compact ? 13 : 14,
                    // Codex uses a medium-weight label for compact composer
                    // controls; heavier weights make the pills look denser
                    // than the surrounding input text.
                    fontWeight: compact ? FontWeight.w600 : FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: compact ? 2 : 4),
              Icon(
                RecodexIcons.chevronDown,
                size: compact ? 17 : 18,
                color: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
