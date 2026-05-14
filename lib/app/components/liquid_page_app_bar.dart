import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class LiquidPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LiquidPageAppBar({
    required this.title,
    this.showMore = false,
    super.key,
  });

  final String title;
  final bool showMore;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return AppBar(
      leadingWidth: 72,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: _LiquidBackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      title: Text(
        title,
        style: TextStyle(color: colors.icon, fontWeight: FontWeight.w900),
      ),
      actions: [
        if (showMore)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Icon(Icons.more_vert, color: colors.icon, size: 24),
          )
        else
          const SizedBox(width: 56),
      ],
    );
  }
}

class _LiquidBackButton extends StatelessWidget {
  const _LiquidBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SizedBox.square(
        dimension: 38,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colors.headerShadow.withValues(
                  alpha: isDark ? 0.42 : 0.16,
                ),
                offset: const Offset(0, 10),
                blurRadius: 22,
              ),
              BoxShadow(
                color: colors.glassHighlight.withValues(
                  alpha: isDark ? 0.08 : 0.54,
                ),
                offset: const Offset(-4, -4),
                blurRadius: 12,
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.glassHighlight.withValues(
                        alpha: isDark ? 0.22 : 0.92,
                      ),
                      colors.glassColor.withValues(alpha: isDark ? 0.70 : 0.66),
                      colors.surfaceOverlay.withValues(
                        alpha: isDark ? 0.38 : 0.58,
                      ),
                    ],
                  ),
                  border: Border.all(
                    color: colors.glassBorder.withValues(
                      alpha: isDark ? 0.72 : 1,
                    ),
                    width: 1.15,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 0),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.icon,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
