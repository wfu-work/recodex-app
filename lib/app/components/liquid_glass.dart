import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 34,
    this.borderRadius,
    this.opacity = 0.64,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final BorderRadius? borderRadius;
  final double opacity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = borderRadius ?? BorderRadius.circular(radius);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassColor.withValues(alpha: opacity),
        borderRadius: shape,
        border: Border.all(
          color: colors.glassBorder.withValues(alpha: isDark ? 0.88 : 0.78),
          width: isDark ? 0.8 : 1,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: shape, onTap: onTap, child: content),
    );
  }
}

class LiquidIconButton extends StatelessWidget {
  const LiquidIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36,
    this.iconSize,
    this.color,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double? iconSize;
  final Color? color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        onPressed: loading ? null : onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        iconSize: iconSize ?? size * 0.52,
        visualDensity: VisualDensity.standard,
        color: color ?? colors.icon,
        disabledColor: (color ?? colors.icon).withValues(alpha: 0.36),
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: loading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: (iconSize ?? size * 0.52) * 0.78,
                  height: (iconSize ?? size * 0.52) * 0.78,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color ?? colors.icon,
                  ),
                )
              : Icon(icon, key: const ValueKey('icon')),
        ),
      ),
    );
  }
}

class BluePillButton extends StatelessWidget {
  const BluePillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: isDark ? colors.glassColor : Colors.white,
        disabledBackgroundColor: Theme.of(
          context,
        ).colorScheme.outline.withValues(alpha: 0.34),
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
