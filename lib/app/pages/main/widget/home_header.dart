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
    this.refreshing = false,
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
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 600;
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
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 36,
          topPadding + 12,
          compact ? 12 : 24,
          8,
        ),
        child: Row(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compact ? 44 : null,
              height: compact ? 44 : null,
              child: Builder(
                builder: (context) => LiquidIconButton(
                  icon: RecodexIcons.menu,
                  tooltip: '菜单',
                  size: compact ? 44 : 36,
                  iconSize: compact ? 20 : null,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
            SizedBox(width: compact ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: compact ? 18 : 24,
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
            SizedBox(width: compact ? 8 : 12),
            _HeaderActionMenu(
              compact: compact,
              onRefreshTasks: onRefreshTasks,
              onShowTaskOutput: onShowTaskOutput,
              onCopyTaskOutput: onCopyTaskOutput,
              onRefreshGit: onRefreshGit,
              taskOutputAvailable: taskOutputAvailable,
              refreshing: refreshing,
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
    required this.compact,
    required this.onRefreshTasks,
    required this.onShowTaskOutput,
    required this.onCopyTaskOutput,
    required this.onRefreshGit,
    required this.taskOutputAvailable,
    required this.refreshing,
  });

  final bool compact;
  final VoidCallback? onRefreshTasks;
  final VoidCallback? onShowTaskOutput;
  final VoidCallback? onCopyTaskOutput;
  final VoidCallback? onRefreshGit;
  final bool taskOutputAvailable;
  final bool refreshing;

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
      tooltip: refreshing ? '正在刷新任务' : '工作台操作',
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
        // Match the leading menu's 44px target so both icons share a center
        // and the title stays centered between equal-width controls on phones.
        padding: compact
            ? const EdgeInsets.all(12)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Semantics(
          label: refreshing ? '正在刷新任务' : '工作台操作',
          button: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: refreshing
                ? SizedBox(
                    key: const ValueKey('refreshing'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.text,
                    ),
                  )
                : Icon(
                    RecodexIcons.more,
                    key: const ValueKey('actions'),
                    size: 20,
                    color: colors.text,
                  ),
          ),
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
