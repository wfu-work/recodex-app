import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.75, -0.85),
          radius: 1.35,
          colors: colors.backgroundGradient,
          stops: colors.backgroundStops,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -84,
            top: 130,
            child: _GlowBlob(
              size: 220,
              color: colors.primaryGlow,
            ),
          ),
          Positioned(
            right: -110,
            bottom: 180,
            child: _GlowBlob(
              size: 260,
              color: colors.secondaryGlow,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 96, spreadRadius: 32)],
      ),
    );
  }
}
