import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/recodex_theme.dart';

/// A compact floating control used when the user has moved away from the
/// newest timeline item.
///
/// While a turn is running, the down arrow becomes a play mark surrounded by
/// quiet ripples. This keeps the control useful (it still jumps to the latest
/// output) while communicating that more content may arrive below.
class ScrollToLatestButton extends StatefulWidget {
  const ScrollToLatestButton({
    required this.running,
    required this.reduceMotion,
    required this.onPressed,
    super.key,
  });

  final bool running;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  State<ScrollToLatestButton> createState() => _ScrollToLatestButtonState();
}

class _ScrollToLatestButtonState extends State<ScrollToLatestButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rippleController;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        widget.reduceMotion ||
        MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ScrollToLatestButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running ||
        oldWidget.reduceMotion != widget.reduceMotion) {
      _reduceMotion =
          widget.reduceMotion ||
          MediaQuery.of(context).disableAnimations ||
          MediaQuery.of(context).accessibleNavigation;
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final shouldAnimate = widget.running && !_reduceMotion;
    if (shouldAnimate) {
      if (!_rippleController.isAnimating) _rippleController.repeat();
    } else {
      _rippleController.stop();
      _rippleController.value = 0;
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final tooltip = widget.running ? '回到最新内容（任务进行中）' : '回到最新内容';
    final icon = widget.running
        ? AnimatedBuilder(
            animation: _rippleController,
            builder: (context, _) {
              return CustomPaint(
                painter: _LatestActivityRipplePainter(
                  progress: _rippleController.value,
                  color: colors.text,
                ),
                child: const Center(child: Icon(RecodexIcons.play, size: 18)),
              );
            },
          )
        : const Center(child: Icon(RecodexIcons.arrowDown, size: 20));

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: colors.glassColor.withValues(alpha: 0.96),
          shape: const CircleBorder(),
          elevation: 5,
          shadowColor: colors.glassShadow.withValues(alpha: 0.42),
          child: InkWell(
            onTap: widget.onPressed,
            customBorder: const CircleBorder(),
            splashColor: colors.text.withValues(alpha: 0.12),
            highlightColor: colors.text.withValues(alpha: 0.06),
            child: SizedBox(
              width: 46,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.glassBorder.withValues(alpha: 0.86),
                  ),
                ),
                child: IconTheme(
                  data: IconThemeData(color: colors.text),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestActivityRipplePainter extends CustomPainter {
  const _LatestActivityRipplePainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortestSide = math.min(size.width, size.height);
    final baseRadius = shortestSide * 0.23;
    for (var index = 0; index < 2; index += 1) {
      final phase = (progress + index * 0.5) % 1;
      final radius = baseRadius + phase * shortestSide * 0.22;
      final opacity = (1 - phase) * 0.24;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LatestActivityRipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
