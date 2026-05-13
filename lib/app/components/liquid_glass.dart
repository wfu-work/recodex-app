import 'dart:ui';

import 'package:flutter/material.dart';

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
    final shape = BorderRadius.circular(radius);
    final content = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: shape,
            border: Border.all(color: Colors.white.withValues(alpha: 0.66)),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.78),
                offset: const Offset(-10, -10),
                blurRadius: 28,
              ),
              BoxShadow(
                color: const Color(0xff9da8b7).withValues(alpha: 0.17),
                offset: const Offset(18, 24),
                blurRadius: 44,
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
    this.size = 56,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: SizedBox.square(
        dimension: size,
        child: LiquidGlass(
          padding: EdgeInsets.zero,
          radius: size / 2,
          opacity: 0.58,
          onTap: onPressed,
          child: Icon(icon, color: const Color(0xff005fc7), size: size * 0.48),
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
        backgroundColor: const Color(0xff005fc7),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xffd8dde7),
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const StadiumBorder(),
        elevation: 8,
        shadowColor: const Color(0xff005fc7).withValues(alpha: 0.28),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
