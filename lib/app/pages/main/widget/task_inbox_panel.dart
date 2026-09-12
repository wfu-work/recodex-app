import 'package:flutter/material.dart';

import '../../../components/liquid_glass.dart';
import '../../../models/bridge_models.dart';
import '../../../theme/recodex_theme.dart';

/// A compact task inbox that mirrors Codex's priority and recency grouping.
///
/// Archived sessions are intentionally omitted. Pinned sessions are shown in
/// the priority group, while the remaining sessions are grouped by their
/// local calendar date and sorted with the shared session ordering contract.
class TaskInboxPanel extends StatelessWidget {
  const TaskInboxPanel({
    required this.sessions,
    required this.selectedSessionId,
    required this.onSelect,
    this.onRefresh,
    this.showRefresh = false,
    super.key,
  });

  final List<SessionRecord> sessions;
  final String? selectedSessionId;
  final ValueChanged<SessionRecord> onSelect;
  final VoidCallback? onRefresh;
  final bool showRefresh;

  List<_TaskGroup> _groups() {
    final visible = sessions.where((session) => !session.isArchived).toList()
      ..sort(compareSessionRecords);
    final groups = <_TaskGroup>[];
    final pinned = visible.where((session) => session.isPinned).toList();
    if (pinned.isNotEmpty) {
      groups.add(_TaskGroup('优先级', pinned));
    }

    final byDay = <DateTime, List<SessionRecord>>{};
    for (final session in visible.where((session) => !session.isPinned)) {
      final local = session.recencyAtDate.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      byDay.putIfAbsent(day, () => <SessionRecord>[]).add(session);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final day in days) {
      groups.add(_TaskGroup(_dateLabel(day), byDay[day]!));
    }
    return groups;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '昨天';
    if (difference > 1 && difference < 7) {
      const weekdays = <String>[
        '星期一',
        '星期二',
        '星期三',
        '星期四',
        '星期五',
        '星期六',
        '星期日',
      ];
      return weekdays[date.weekday - 1];
    }
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final groups = _groups();
    return Material(
      color: Colors.transparent,
      child: LiquidGlass(
        padding: EdgeInsets.zero,
        radius: 24,
        opacity: 0.94,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 660),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PanelHeader(
                count: sessions.where((session) => !session.isArchived).length,
                onRefresh: showRefresh ? onRefresh : null,
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: colors.glassBorder.withValues(alpha: 0.42),
              ),
              Flexible(
                child: groups.isEmpty
                    ? const _EmptyTaskInbox()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                        shrinkWrap: true,
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return _TaskGroupSection(
                            group: group,
                            selectedSessionId: selectedSessionId,
                            onSelect: onSelect,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskGroup {
  const _TaskGroup(this.label, this.sessions);

  final String label;
  final List<SessionRecord> sessions;
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.count, this.onRefresh});

  final int count;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
      child: Row(
        children: [
          Icon(RecodexIcons.notificationsActive, size: 19, color: colors.icon),
          const SizedBox(width: 10),
          Text(
            '任务',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            Tooltip(
              message: '刷新任务',
              child: IconButton(
                onPressed: onRefresh,
                icon: const Icon(RecodexIcons.sync, size: 18),
                color: colors.icon,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskGroupSection extends StatelessWidget {
  const _TaskGroupSection({
    required this.group,
    required this.selectedSessionId,
    required this.onSelect,
  });

  final _TaskGroup group;
  final String? selectedSessionId;
  final ValueChanged<SessionRecord> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
            child: Text(
              group.label,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.35,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceOverlay.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (var index = 0; index < group.sessions.length; index++) ...[
                  _TaskInboxRow(
                    session: group.sessions[index],
                    selected: group.sessions[index].id == selectedSessionId,
                    onTap: () => onSelect(group.sessions[index]),
                  ),
                  if (index != group.sessions.length - 1)
                    Divider(
                      height: 1,
                      indent: 44,
                      endIndent: 12,
                      color: colors.glassBorder.withValues(alpha: 0.3),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskInboxRow extends StatelessWidget {
  const _TaskInboxRow({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final SessionRecord session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final iconColor = session.isRunning ? colors.success : colors.icon;
    return Material(
      color: selected
          ? colors.surfaceOverlay.withValues(alpha: 0.7)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(
                  session.isPinned ? RecodexIcons.pin : RecodexIcons.message,
                  size: 17,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ),
              if (session.isRunning) ...[
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTaskInbox extends StatelessWidget {
  const _EmptyTaskInbox();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(RecodexIcons.message, size: 28, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            '暂无任务',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '新建对话后，任务会显示在这里',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
