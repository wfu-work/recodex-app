import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class LiquidPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LiquidPageAppBar({
    required this.title,
    this.showMore = false,
    this.onBack,
    super.key,
  });

  final String title;
  final bool showMore;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return AppBar(
      leadingWidth: 56,
      leading: IconButton(
        tooltip: '返回',
        onPressed: onBack ?? () => Navigator.of(context).pop(),
        icon: Icon(RecodexIcons.back, color: colors.text, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
      ),
      actions: [
        if (showMore)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Icon(RecodexIcons.more, color: colors.text, size: 22),
          )
        else
          const SizedBox(width: 56),
      ],
    );
  }
}
