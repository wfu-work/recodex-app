import 'package:flutter/material.dart';

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.75, -0.85),
          radius: 1.25,
          colors: [Color(0xffeef4ff), Color(0xfffcf8f8), Color(0xfff6f2f6)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -84,
            top: 130,
            child: _GlowBlob(
              size: 220,
              color: const Color(0xffd9e8ff).withValues(alpha: 0.72),
            ),
          ),
          Positioned(
            right: -110,
            bottom: 180,
            child: _GlowBlob(
              size: 260,
              color: const Color(0xffffeef8).withValues(alpha: 0.82),
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
