import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
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
  final TextEditingController _searchController = TextEditingController();
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
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '任务历史'),
          body: SettingsPageContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                SettingsSectionTitle(
                  title: '全部任务 · ${bridge.sessions.length}',
                  subtitle: '搜索、筛选并重新打开已经创建的 Codex 任务。',
                ),
                const SizedBox(height: 12),
                SettingsCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    key: const ValueKey('task-history-search'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      icon: Icon(
                        RecodexIcons.search,
                        color: context.recodexColors.icon,
                      ),
                      hintText: '搜索任务名称或内容',
                      border: InputBorder.none,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(RecodexIcons.close),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _FilterBar(
                  filter: _filter,
                  sort: _sort,
                  onFilterChanged: (value) => setState(() => _filter = value),
                  onSortChanged: (value) => setState(() => _sort = value),
                ),
                const SizedBox(height: 14),
                ..._filteredSessions(bridge.sessions).map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HistoryTaskTile(
                      session: session,
                      onTap: () {
                        bridge.selectSession(session);
                        Get.offNamed(Routes.main);
                      },
                    ),
                  ),
                ),
                if (_filteredSessions(bridge.sessions).isEmpty)
                  SettingsCard(
                    child: Column(
                      children: [
                        Icon(
                          RecodexIcons.search,
                          size: 28,
                          color: context.recodexColors.textMuted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bridge.sessions.isEmpty ? '暂无任务记录' : '没有匹配的任务',
                          style: TextStyle(
                            color: context.recodexColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bridge.sessions.isEmpty
                              ? '连接 Relay 后，任务会自动出现在这里。'
                              : '尝试更换关键词或筛选条件。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.recodexColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        if (bridge.connected.value) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: bridge.refreshProjects,
                            icon: const Icon(RecodexIcons.sync, size: 17),
                            label: const Text('刷新任务'),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SessionRecord> _filteredSessions(List<SessionRecord> source) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = source.where((session) {
      final matchesFilter = switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.running => session.isRunning,
        _HistoryFilter.active => !session.isArchived && !session.isRunning,
        _HistoryFilter.archived => session.isArchived,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return session.displayTitle.toLowerCase().contains(query) ||
          session.prompt.toLowerCase().contains(query) ||
          session.workspace.toLowerCase().contains(query);
    }).toList();
    filtered.sort((left, right) {
      return switch (_sort) {
        _HistorySort.recent => compareSessionRecords(left, right),
        _HistorySort.oldest => compareSessionRecords(right, left),
        _HistorySort.title => left.displayTitle.compareTo(right.displayTitle),
      };
    });
    return filtered;
  }
}

enum _HistoryFilter { all, running, active, archived }

enum _HistorySort { recent, oldest, title }

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  final _HistoryFilter filter;
  final _HistorySort sort;
  final ValueChanged<_HistoryFilter> onFilterChanged;
  final ValueChanged<_HistorySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _HistoryFilter.values) ...[
                  ChoiceChip(
                    label: Text(_filterLabel(item)),
                    selected: item == filter,
                    onSelected: (_) => onFilterChanged(item),
                    labelStyle: TextStyle(
                      color: item == filter ? colors.text : colors.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                    side: BorderSide(color: colors.glassBorder),
                    selectedColor: colors.surfaceOverlay,
                    backgroundColor: colors.glassColor,
                    showCheckmark: false,
                  ),
                  if (item != _HistoryFilter.values.last)
                    const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<_HistorySort>(
            value: sort,
            isDense: true,
            icon: Icon(
              RecodexIcons.chevronDown,
              size: 16,
              color: colors.textMuted,
            ),
            onChanged: (value) {
              if (value != null) onSortChanged(value);
            },
            items: [
              for (final item in _HistorySort.values)
                DropdownMenuItem(value: item, child: Text(_sortLabel(item))),
            ],
          ),
        ),
      ],
    );
  }

  String _filterLabel(_HistoryFilter value) {
    return switch (value) {
      _HistoryFilter.all => '全部',
      _HistoryFilter.running => '运行中',
      _HistoryFilter.active => '未归档',
      _HistoryFilter.archived => '已归档',
    };
  }

  String _sortLabel(_HistorySort value) {
    return switch (value) {
      _HistorySort.recent => '最近打开',
      _HistorySort.oldest => '最早创建',
      _HistorySort.title => '按名称',
    };
  }
}

class _HistoryTaskTile extends StatelessWidget {
  const _HistoryTaskTile({required this.session, required this.onTap});

  final SessionRecord session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final subtitle = [
      if (session.workspace.trim().isNotEmpty)
        _lastPathSegment(session.workspace),
      _dateLabel(session.updatedAtDate),
    ].where((value) => value.isNotEmpty).join(' · ');
    return SettingsCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: session.isRunning
                  ? CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: colors.icon,
                    )
                  : Icon(
                      session.isArchived
                          ? RecodexIcons.archive
                          : RecodexIcons.message,
                      size: 20,
                      color: colors.icon,
                    ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(RecodexIcons.chevronRight, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '';
  final now = DateTime.now();
  final local = value.toLocal();
  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '今天 $hour:$minute';
  }
  return '${local.month}月${local.day}日';
}

String _lastPathSegment(String value) {
  final normalized = value.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (normalized.isEmpty) return '';
  return normalized.split('/').last;
}
