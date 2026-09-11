import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../models/bridge_models.dart';
import '../../routes/app_pages.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import 'settings_widgets.dart';

class TaskHistoryPage extends StatefulWidget {
  const TaskHistoryPage({super.key});

  @override
  State<TaskHistoryPage> createState() => _TaskHistoryPageState();
}

class _TaskHistoryPageState extends State<TaskHistoryPage> {
  final _searchController = TextEditingController();
  _HistoryFilter _filter = _HistoryFilter.all;
  _HistorySort _sort = _HistorySort.recent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = Get.find<BridgeController>();
    final colors = context.recodexColors;
    return Obx(() {
      final sessions = bridge.sessions.toList();
      final filtered = _filteredSessions(sessions);
      final counts = {
        for (final filter in _HistoryFilter.values)
          filter: sessions
              .where((session) => _matchesFilter(session, filter))
              .length,
      };
      final workspaces = filtered
          .map((session) => session.workspace.trim())
          .where((workspace) => workspace.isNotEmpty)
          .toSet()
          .length;
      final hasQuery = _searchController.text.trim().isNotEmpty;
      final connected = bridge.connected.value;
      return LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '任务历史'),
          body: SettingsPageContent(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
                final availableWidth = constraints.maxWidth - padding * 2;
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final wide = availableWidth / scale >= 860;
                final inlineToolbar = availableWidth / scale >= 1040;
                return CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padding, 24, padding, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  hasQuery
                                      ? '搜索结果'
                                      : _filter == _HistoryFilter.all
                                      ? '全部任务'
                                      : _filter.label,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${filtered.length} 项任务',
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                                if (workspaces > 0)
                                  Text(
                                    '·  $workspaces 个工作区',
                                    style: TextStyle(
                                      color: colors.textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _HistoryToolbar(
                              search: _HistorySearchField(
                                controller: _searchController,
                                onChanged: () => setState(() {}),
                              ),
                              inline: inlineToolbar,
                              filter: _filter,
                              sort: _sort,
                              counts: counts,
                              onFilterChanged: (value) =>
                                  setState(() => _filter = value),
                              onSortChanged: (value) =>
                                  setState(() => _sort = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                      sliver: filtered.isEmpty
                          ? SliverToBoxAdapter(
                              child: _HistoryEmptyState(
                                hasTasks: sessions.isNotEmpty,
                                onReset: sessions.isEmpty
                                    ? null
                                    : () => setState(() {
                                        _searchController.clear();
                                        _filter = _HistoryFilter.all;
                                      }),
                                onRefresh: connected
                                    ? bridge.refreshProjects
                                    : null,
                              ),
                            )
                          : DecoratedSliver(
                              decoration: BoxDecoration(
                                color: colors.glassColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.glassBorder),
                              ),
                              sliver: SliverMainAxisGroup(
                                slivers: [
                                  if (wide)
                                    SliverToBoxAdapter(
                                      child: _HistoryTableHeader(),
                                    ),
                                  SliverList.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final session = filtered[index];
                                      return _HistoryTaskRow(
                                        key: ValueKey(
                                          'history-task-${session.id}',
                                        ),
                                        session: session,
                                        wide: wide,
                                        first: index == 0,
                                        last: index == filtered.length - 1,
                                        onTap: () {
                                          bridge.selectSession(session);
                                          Get.offNamed(Routes.main);
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    });
  }

  List<SessionRecord> _filteredSessions(List<SessionRecord> source) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = source.where((session) {
      if (!_matchesFilter(session, _filter)) return false;
      return query.isEmpty ||
          session.displayTitle.toLowerCase().contains(query) ||
          session.prompt.toLowerCase().contains(query) ||
          session.workspace.toLowerCase().contains(query);
    }).toList();
    filtered.sort(
      (left, right) => switch (_sort) {
        _HistorySort.recent => compareSessionRecords(left, right),
        _HistorySort.oldest => compareSessionRecords(right, left),
        _HistorySort.title => left.displayTitle.compareTo(right.displayTitle),
      },
    );
    return filtered;
  }
}

enum _HistoryFilter {
  all('全部'),
  running('运行中'),
  active('未归档'),
  archived('已归档');

  const _HistoryFilter(this.label);
  final String label;
}

enum _HistorySort {
  recent('最近打开'),
  oldest('最早打开'),
  title('按名称');

  const _HistorySort(this.label);
  final String label;
}

bool _matchesFilter(SessionRecord session, _HistoryFilter filter) =>
    switch (filter) {
      _HistoryFilter.all => true,
      _HistoryFilter.running => session.isRunning,
      _HistoryFilter.active => !session.isArchived && !session.isRunning,
      _HistoryFilter.archived => session.isArchived,
    };

class _HistorySearchField extends StatelessWidget {
  const _HistorySearchField({
    required this.controller,
    required this.onChanged,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.glassBorder),
    );
    return TextField(
      key: const ValueKey('task-history-search'),
      controller: controller,
      onChanged: (_) => onChanged(),
      style: TextStyle(color: colors.text, fontSize: 14, height: 1.4),
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: '搜索任务、内容或工作区',
        hintStyle: TextStyle(
          color: colors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: colors.glassColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        prefixIcon: Icon(
          RecodexIcons.search,
          size: 18,
          color: colors.textMuted,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.textMuted, width: 1.2),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
                icon: const Icon(RecodexIcons.close, size: 16),
              ),
      ),
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  const _HistoryToolbar({
    required this.search,
    required this.inline,
    required this.filter,
    required this.sort,
    required this.counts,
    required this.onFilterChanged,
    required this.onSortChanged,
  });
  final Widget search;
  final bool inline;
  final _HistoryFilter filter;
  final _HistorySort sort;
  final Map<_HistoryFilter, int> counts;
  final ValueChanged<_HistoryFilter> onFilterChanged;
  final ValueChanged<_HistorySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final filters = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final item in _HistoryFilter.values)
          Semantics(
            selected: item == filter,
            child: TextButton(
              onPressed: () => onFilterChanged(item),
              style: TextButton.styleFrom(
                foregroundColor: item == filter
                    ? colors.text
                    : colors.textMuted,
                backgroundColor: item == filter
                    ? colors.surfaceOverlay
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: item == filter
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.label),
                  const SizedBox(width: 6),
                  Text(
                    '${counts[item] ?? 0}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final sortButton = RecodexDropdown<_HistorySort>(
      value: sort,
      tooltip: '任务排序',
      compact: true,
      showBorder: false,
      maxWidth: 175,
      options: [
        for (final item in _HistorySort.values)
          RecodexDropdownOption(value: item, label: item.label),
      ],
      onChanged: onSortChanged,
    );
    if (inline) {
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 20),
          filters,
          const SizedBox(width: 16),
          sortButton,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        search,
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
            if (constraints.maxWidth / scale < 540) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  filters,
                  Align(alignment: Alignment.centerRight, child: sortButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: filters),
                const SizedBox(width: 16),
                sortButton,
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Shared column widths keep the heading and virtualized rows aligned.
class _HistoryColumns extends StatelessWidget {
  const _HistoryColumns({
    required this.task,
    required this.workspace,
    required this.status,
    required this.time,
    required this.trailing,
  });
  final Widget task;
  final Widget workspace;
  final Widget status;
  final Widget time;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: task),
      const SizedBox(width: 24),
      SizedBox(width: 180, child: workspace),
      const SizedBox(width: 24),
      SizedBox(width: 96, child: status),
      const SizedBox(width: 24),
      SizedBox(width: 112, child: time),
      const SizedBox(width: 16),
      SizedBox(width: 16, child: trailing),
    ],
  );
}

class _HistoryTableHeader extends StatelessWidget {
  const _HistoryTableHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.glassBorder)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12, color: colors.textMuted),
        child: const _HistoryColumns(
          task: Padding(padding: EdgeInsets.only(left: 32), child: Text('任务')),
          workspace: Text('工作区'),
          status: Text('状态'),
          time: Text('最近打开'),
          trailing: SizedBox(),
        ),
      ),
    );
  }
}

class _HistoryTaskRow extends StatelessWidget {
  const _HistoryTaskRow({
    required this.session,
    required this.wide,
    required this.first,
    required this.last,
    required this.onTap,
    super.key,
  });
  final SessionRecord session;
  final bool wide;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final time = _dateLabel(session.recencyAtDate);
    final task = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            session.isPinned
                ? RecodexIcons.pin
                : session.isArchived
                ? RecodexIcons.archive
                : RecodexIcons.message,
            size: 16,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            session.displayTitle,
            maxLines: wide ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
    final workspace = _WorkspaceLabel(workspace: session.workspace);
    final status = _TaskStatus(session: session);
    final trailing = Icon(
      RecodexIcons.chevronRight,
      size: 16,
      color: colors.textMuted.withValues(alpha: 0.6),
    );
    return Column(
      children: [
        if (!first)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 0.6,
              color: colors.glassBorder,
            ),
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.vertical(
              top: first && !wide ? const Radius.circular(12) : Radius.zero,
              bottom: last ? const Radius.circular(12) : Radius.zero,
            ),
            hoverColor: colors.surfaceOverlay,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: wide
                  ? _HistoryColumns(
                      task: task,
                      workspace: workspace,
                      status: status,
                      time: Tooltip(
                        message: _fullDateLabel(session.recencyAtDate),
                        child: Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                      trailing: trailing,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: task),
                            const SizedBox(width: 12),
                            trailing,
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              workspace,
                              status,
                              Text(
                                time,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkspaceLabel extends StatelessWidget {
  const _WorkspaceLabel({required this.workspace});
  final String workspace;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final name = _lastPathSegment(workspace);
    return Tooltip(
      message: workspace.isEmpty ? '未指定工作区' : workspace,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(RecodexIcons.folder, size: 13, color: colors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name.isEmpty ? '未指定' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskStatus extends StatelessWidget {
  const _TaskStatus({required this.session});
  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final status = session.status.trim().toLowerCase();
    final label = session.isRunning
        ? '运行中'
        : session.isArchived
        ? '已归档'
        : switch (status) {
            'completed' || 'done' || 'success' => '已完成',
            'failed' || 'error' => '失败',
            'interrupted' || 'aborted' || 'cancelled' || 'canceled' => '已中断',
            _ => '未归档',
          };
    final color = session.isRunning
        ? RecodexTheme.codexBlue
        : label == '失败'
        ? colors.error
        : colors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: session.isRunning ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({
    required this.hasTasks,
    this.onReset,
    this.onRefresh,
  });
  final bool hasTasks;
  final VoidCallback? onReset;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => SettingsCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            RecodexIcons.search,
            size: 24,
            color: context.recodexColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            hasTasks ? '没有匹配的任务' : '暂无任务记录',
            style: TextStyle(
              color: context.recodexColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasTasks ? '试试其他关键词，或清除筛选。' : '连接 Relay 后，任务会自动出现在这里。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.recodexColors.textMuted,
              fontSize: 13,
            ),
          ),
          if (onReset != null)
            TextButton(onPressed: onReset, child: const Text('清除筛选'))
          else if (onRefresh != null)
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(RecodexIcons.sync, size: 16),
              label: const Text('刷新任务'),
            ),
        ],
      ),
    ),
  );
}

String _dateLabel(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '时间未记录';
  final now = DateTime.now();
  final local = value.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (day == today) return '今天 $clock';
  if (day == DateTime(now.year, now.month, now.day - 1)) return '昨天 $clock';
  if (local.year != now.year) {
    return '${local.year}/${local.month}/${local.day}';
  }
  return '${local.month}月${local.day}日 $clock';
}

String _fullDateLabel(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '时间未记录';
  return value.toLocal().toString().split('.').first;
}

String _lastPathSegment(String value) {
  final normalized = value.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return normalized.isEmpty ? '' : normalized.split('/').last;
}
