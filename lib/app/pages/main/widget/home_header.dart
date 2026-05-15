import 'package:flutter/material.dart';

import '../../../components/liquid_glass.dart';
import '../../../components/status_chips.dart';
import '../../../theme/recodex_theme.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.title,
    required this.subtitle,
    required this.changedFiles,
    required this.added,
    required this.removed,
    required this.backgroundProgress,
    required this.topPadding,
    required this.onRefreshGit,
    super.key,
  });

  final String title;
  final String subtitle;
  final int changedFiles;
  final int added;
  final int removed;
  final double backgroundProgress;
  final double topPadding;
  final VoidCallback? onRefreshGit;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundAlpha = 0.28 + backgroundProgress * 0.46;
    final tintAlpha = 0.30 + backgroundProgress * 0.24;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  colors.headerColor.withValues(alpha: backgroundAlpha + 0.10),
                  colors.surfaceOverlay.withValues(alpha: tintAlpha),
                ]
              : [
                  const Color(0xffe8f1ff).withValues(alpha: tintAlpha),
                  colors.headerColor.withValues(alpha: backgroundAlpha),
                ],
        ),
        border: Border(
          bottom: BorderSide(
            color: colors.headerBorder.withValues(
              alpha: 0.12 + backgroundProgress * 0.42,
            ),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(
              alpha: (isDark ? 0.18 : 0.07) + backgroundProgress * 0.09,
            ),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(36, topPadding + 12, 24, 8),
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
              child: DiffChip(
                changedFiles: changedFiles,
                added: added,
                removed: removed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
