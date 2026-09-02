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
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final backButton = IconButton(
      tooltip: '返回',
      onPressed: onBack ?? () => Navigator.of(context).pop(),
      icon: Icon(RecodexIcons.back, color: colors.text, size: 22),
    );
    return AppBar(
      // The macOS window buttons occupy the first ~70 logical pixels of the
      // full-size titlebar. Keep the back affordance in its own lane so it
      // never paints underneath the native traffic lights.
      leadingWidth: isMacOS ? 112 : 56,
      leading: isMacOS
          ? Padding(padding: const EdgeInsets.only(left: 56), child: backButton)
          : backButton,
      title: Text(
        title,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
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
