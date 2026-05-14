import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 34,
    this.opacity = 0.64,
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
    final shape = BorderRadius.circular(radius);
    final content = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassColor.withValues(alpha: opacity),
            borderRadius: shape,
            border: Border.all(color: colors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: colors.glassHighlight,
                offset: const Offset(-8, -8),
                blurRadius: 24,
              ),
              BoxShadow(
                color: colors.glassShadow,
                offset: const Offset(0, 18),
                blurRadius: 38,
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
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
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Tooltip(
      message: tooltip ?? '',
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.glassColor.withValues(alpha: 0.72),
            border: Border.all(color: colors.glassBorder),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, color: colors.icon, size: size * 0.48),
            ),
          ),
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
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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
