import 'package:flutter/material.dart';

import '../../../components/liquid_glass.dart';
import '../../../components/recodex_dropdown.dart';
import '../../../theme/recodex_theme.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.title,
    required this.subtitle,
    required this.backgroundProgress,
    required this.topPadding,
    this.onRefreshTasks,
    this.onShowTaskOutput,
    this.onCopyTaskOutput,
    required this.onRefreshGit,
    this.taskOutputAvailable = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final double backgroundProgress;
  final double topPadding;
  final VoidCallback? onRefreshTasks;
  final VoidCallback? onShowTaskOutput;
  final VoidCallback? onCopyTaskOutput;
  final VoidCallback? onRefreshGit;
  final bool taskOutputAvailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = Curves.easeOutCubic.transform(
      backgroundProgress.clamp(0.0, 1.0),
    );
    // Keep the resting header light enough to reveal the workspace backdrop,
    // then make it fully opaque as content passes underneath.
    final restingColor = colors.headerColor.withValues(
      alpha: isDark ? 0.56 : 0.68,
    );
    final solidColor = isDark
        ? Color.lerp(colors.headerColor, colors.headerShadow, 0.16)!
        : Color.lerp(colors.headerColor, colors.headerShadow, 0.22)!;
    final backgroundColor = Color.lerp(restingColor, solidColor, progress)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: colors.headerBorder.withValues(
              alpha: 0.14 + progress * 0.42,
            ),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(
              alpha: (isDark ? 0.16 : 0.06) + progress * 0.1,
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
                icon: RecodexIcons.menu,
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      height: 1.12,
                      fontWeight: FontWeight.w600,
                    ),
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
                        fontWeight: FontWeight.w500,
                        height: 1.08,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HeaderActionMenu(
              onRefreshTasks: onRefreshTasks,
              onShowTaskOutput: onShowTaskOutput,
              onCopyTaskOutput: onCopyTaskOutput,
              onRefreshGit: onRefreshGit,
              taskOutputAvailable: taskOutputAvailable,
            ),
          ],
        ),
      ),
    );
  }
}

enum _HomeHeaderAction {
  refreshTasks,
  showTaskOutput,
  copyTaskOutput,
  refreshGit,
}

class _HeaderActionMenu extends StatelessWidget {
  const _HeaderActionMenu({
    required this.onRefreshTasks,
    required this.onShowTaskOutput,
    required this.onCopyTaskOutput,
    required this.onRefreshGit,
    required this.taskOutputAvailable,
  });

  final VoidCallback? onRefreshTasks;
  final VoidCallback? onShowTaskOutput;
  final VoidCallback? onCopyTaskOutput;
  final VoidCallback? onRefreshGit;
  final bool taskOutputAvailable;

  void _onSelected(_HomeHeaderAction action) {
    switch (action) {
      case _HomeHeaderAction.refreshTasks:
        onRefreshTasks?.call();
      case _HomeHeaderAction.showTaskOutput:
        onShowTaskOutput?.call();
      case _HomeHeaderAction.copyTaskOutput:
        onCopyTaskOutput?.call();
      case _HomeHeaderAction.refreshGit:
        onRefreshGit?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return RecodexPopupMenuButton<_HomeHeaderAction>(
      tooltip: '工作台操作',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      onSelected: _onSelected,
      itemBuilder: (context) => [
        _actionItem(
          context,
          action: _HomeHeaderAction.refreshTasks,
          icon: RecodexIcons.sync,
          label: '刷新当前项目任务',
          enabled: onRefreshTasks != null,
        ),
        _actionItem(
          context,
          action: _HomeHeaderAction.showTaskOutput,
          icon: RecodexIcons.terminal,
          label: '查看任务输出',
          enabled: taskOutputAvailable && onShowTaskOutput != null,
        ),
        _actionItem(
          context,
          action: _HomeHeaderAction.copyTaskOutput,
          icon: RecodexIcons.copy,
          label: '复制任务输出',
          enabled: taskOutputAvailable && onCopyTaskOutput != null,
        ),
        const PopupMenuDivider(),
        _actionItem(
          context,
          action: _HomeHeaderAction.refreshGit,
          icon: RecodexIcons.gitCompare,
          label: '刷新 Git 状态',
          enabled: onRefreshGit != null,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Semantics(
          label: '工作台操作',
          button: true,
          child: Icon(RecodexIcons.more, size: 20, color: colors.text),
        ),
      ),
    );
  }

  PopupMenuItem<_HomeHeaderAction> _actionItem(
    BuildContext context, {
    required _HomeHeaderAction action,
    required IconData icon,
    required String label,
    required bool enabled,
  }) {
    final colors = context.recodexColors;
    final foreground = enabled
        ? colors.text
        : colors.textMuted.withValues(alpha: 0.5);
    return PopupMenuItem<_HomeHeaderAction>(
      value: action,
      enabled: enabled,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: enabled ? colors.icon : foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}
