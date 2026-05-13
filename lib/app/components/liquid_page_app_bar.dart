import 'package:flutter/material.dart';

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
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xff005fc7), size: 32),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xff005fc7),
          fontWeight: FontWeight.w900,
        ),
      ),
      actions: [
        if (showMore)
          const Padding(
            padding: EdgeInsets.only(right: 18),
            child: Icon(Icons.more_vert, color: Color(0xff005fc7), size: 32),
          )
        else
          const SizedBox(width: 56),
      ],
    );
  }
}
