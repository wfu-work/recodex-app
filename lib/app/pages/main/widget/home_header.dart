import 'package:flutter/material.dart';

import '../../../components/liquid_glass.dart';
import '../../../components/status_chips.dart';
import '../../../theme/recodex_theme.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.title,
    required this.subtitle,
    required this.added,
    required this.removed,
    required this.backgroundProgress,
    required this.topPadding,
    required this.onRefreshGit,
    super.key,
  });

  final String title;
  final String subtitle;
  final int added;
  final int removed;
  final double backgroundProgress;
  final double topPadding;
  final VoidCallback? onRefreshGit;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.headerColor.withValues(
          alpha: 0.18 + backgroundProgress * 0.78,
        ),
        border: Border(
          bottom: BorderSide(
            color: colors.headerBorder.withValues(
              alpha: backgroundProgress * 0.52,
            ),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(
              alpha: backgroundProgress * 0.11,
            ),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(36, topPadding + 12, 24, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) => LiquidIconButton(
                icon: Icons.menu,
                tooltip: '菜单',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 28),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onRefreshGit,
              child: DiffChip(added: added, removed: removed),
            ),
          ],
        ),
      ),
    );
  }
}
