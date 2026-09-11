import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

/// Three gently moving dots that indicate ongoing work in the
/// jump-to-latest control.
class RecodexActivityRipple extends StatefulWidget {
  const RecodexActivityRipple({
    this.size = 28,
    this.reduceMotion = false,
    this.color,
    super.key,
  });

  final double size;
  final bool reduceMotion;
  final Color? color;

  @override
  State<RecodexActivityRipple> createState() => _RecodexActivityRippleState();
}

class _RecodexActivityRippleState extends State<RecodexActivityRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant RecodexActivityRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) _syncMotion();
  }

  void _syncMotion() {
    final media = MediaQuery.of(context);
    // Accessible navigation (for example, a screen reader) does not request
    // reduced motion. Only explicit motion preferences pause this indicator.
    final reduceMotion = widget.reduceMotion || media.disableAnimations;
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      if (_reduceMotion) {
        _controller
          ..stop()
          ..value = 0;
      } else {
        _controller.repeat();
      }
    } else if (!_reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.recodexColors.textMuted;
    final size = widget.size;
    return SizedBox.square(
      dimension: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ActivityRipplePainter(
            progress: _reduceMotion ? 0 : _controller.value,
            color: color,
            size: size,
            reduceMotion: _reduceMotion,
          ),
        ),
      ),
    );
  }
}

class _ActivityRipplePainter extends CustomPainter {
  const _ActivityRipplePainter({
    required this.progress,
    required this.color,
    required this.size,
    required this.reduceMotion,
  });

  final double progress;
  final Color color;
  final double size;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = canvasSize.center(Offset.zero);
    final dotSize = math.max(3, size * 0.19);
    final dotSpacing = dotSize * 0.72;
    final dotStart = center.dx - dotSize - dotSpacing;
    for (var index = 0; index < 3; index += 1) {
      final phase = (progress + index * 0.17) % 1;
      final lift = reduceMotion
          ? 0.0
          : -math.sin(phase * math.pi * 2) * size * 0.12;
      final opacity = reduceMotion
          ? 0.64
          : (0.44 + (math.sin(phase * math.pi * 2) + 1) * 0.22)
                .clamp(0.36, 0.9)
                .toDouble();
      canvas.drawCircle(
        Offset(dotStart + index * (dotSize + dotSpacing), center.dy + lift),
        dotSize / 2,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityRipplePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.size != size ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

/// A restrained sweeping highlight for text that represents live work.
///
/// It intentionally falls back to the supplied text style when reduced motion
/// is requested, while keeping the semantic text unchanged for screen readers.
class RecodexActivityShimmerText extends StatefulWidget {
  const RecodexActivityShimmerText({
    required this.text,
    required this.style,
    this.reduceMotion = false,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    super.key,
  });

  final String text;
  final TextStyle style;
  final bool reduceMotion;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  State<RecodexActivityShimmerText> createState() =>
      _RecodexActivityShimmerTextState();
}

class _RecodexActivityShimmerTextState extends State<RecodexActivityShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant RecodexActivityShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) _syncMotion();
  }

  void _syncMotion() {
    final media = MediaQuery.of(context);
    // Screen readers enable accessible navigation, not reduced motion. Use
    // the same explicit motion preferences as the running dots above.
    final reduceMotion = widget.reduceMotion || media.disableAnimations;
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      if (_reduceMotion) {
        _controller
          ..stop()
          ..value = 0;
      } else {
        _controller.repeat();
      }
    } else if (!_reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      style: widget.style,
    );
    if (_reduceMotion) return text;
    final colors = context.recodexColors;
    return AnimatedBuilder(
      animation: _controller,
      child: text,
      builder: (context, child) {
        final begin = -2.2 + _controller.value * 4.4;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(begin, 0),
            end: Alignment(begin + 1, 0),
            colors: [
              colors.textMuted.withValues(alpha: 0.72),
              colors.textMuted.withValues(alpha: 0.72),
              colors.text,
              colors.textMuted.withValues(alpha: 0.72),
              colors.textMuted.withValues(alpha: 0.72),
            ],
            stops: const [0, 0.32, 0.5, 0.68, 1],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
