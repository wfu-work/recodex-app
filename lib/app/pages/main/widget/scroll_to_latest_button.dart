import 'package:flutter/material.dart';

import '../../../components/live_activity.dart';
import '../../../theme/recodex_theme.dart';

/// A compact floating control above the composer for live output and
/// jump-to-latest navigation.
///
/// While a turn is running, the down arrow becomes the quiet ripple mark used
/// for live activity. The control remains a jump-to-latest action in both
/// states; only its visual language changes.
class ScrollToLatestButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final media = MediaQuery.of(context);
    final motionDisabled =
        reduceMotion || media.disableAnimations || media.accessibleNavigation;
    final tooltip = running ? '回到最新内容（任务进行中）' : '回到最新内容';
    final icon = AnimatedSwitcher(
      duration: motionDisabled
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: running
          ? RecodexActivityRipple(
              key: const ValueKey('running-ripple'),
              size: 28,
              reduceMotion: reduceMotion,
              color: colors.text,
            )
          : const Center(
              key: ValueKey('latest-arrow'),
              child: Icon(RecodexIcons.arrowDown, size: 20),
            ),
    );

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: colors.glassColor.withValues(alpha: 0.96),
          shape: const CircleBorder(),
          // The floating control sits over the composer and already has a
          // subtle border. Avoid a second visual layer here so it reads as a
          // lightweight utility action instead of a raised button.
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
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
