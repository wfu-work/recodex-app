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
    return Center(
      child: SizedBox.square(
        dimension: 36,
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
              child: Icon(Icons.arrow_back, color: colors.icon, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
