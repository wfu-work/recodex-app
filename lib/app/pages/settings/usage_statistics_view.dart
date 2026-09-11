import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/usage_heatmap.dart';
import '../../models/bridge_models.dart';
import '../../routes/app_pages.dart';
import '../../services/answer_metadata.dart';
import '../../services/usage_statistics.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import 'settings_widgets.dart';

class UsageStatisticsPage extends StatefulWidget {
  const UsageStatisticsPage({this.now, super.key});
  final DateTime? now;

  @override
  State<UsageStatisticsPage> createState() => _UsageStatisticsPageState();
}

class _UsageStatisticsPageState extends State<UsageStatisticsPage> {
  final _bridge = Get.find<BridgeController>();
  final _search = TextEditingController();
  final _workers = <Worker>[];
  List<AnswerUsageRecord> _records = [];
  int _period = 365;
  int _visibleCount = 50;
  int _generation = 0;
  DateTime? _selectedDay;
  DateTime? _updatedAt;
  bool _loading = true;
  String? _error;

  DateTime get _today => usageDay(widget.now ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _workers.add(
      everAll(
        [
          _bridge.activePairingId,
          _bridge.spaceId,
          _bridge.deviceId,
          _bridge.targetDeviceId,
        ],
        (_) {
          setState(() {
            _records = [];
            _selectedDay = null;
            _updatedAt = null;
          });
          _reload();
        },
      ),
    );
    _workers.add(
      debounce(_bridge.timelineRevision, (_) {
        if (!_bridge.timelineStatus.value.isActive) _reload();
      }, time: const Duration(milliseconds: 800)),
    );
    _reload();
  }

  @override
  void dispose() {
    _generation++;
    for (final worker in _workers) {
      worker.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _bridge.loadUsageStatistics();
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = records;
        _loading = false;
        _updatedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '消耗记录读取失败，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final today = _today;
    final start = shiftUsageDay(today, -(_period == 0 ? 365 : _period) + 1);
    final query = _search.text.trim().toLowerCase();
    final records = _records.where((record) {
      final matches =
          query.isEmpty ||
          '${record.title} ${record.workspace} ${record.threadId}'
              .toLowerCase()
              .contains(query);
      final day = record.day;
      return matches &&
          (_period == 0 ||
              day != null && !day.isBefore(start) && !day.isAfter(today));
    }).toList();
    final totals = UsageTotals(records);
    final days = dailyUsageTotals(
      records.where(
        (record) =>
            record.day != null &&
            !record.day!.isBefore(start) &&
            !record.day!.isAfter(today),
      ),
    );
    final details =
        records
            .where(
              (record) => _selectedDay == null || record.day == _selectedDay,
            )
            .toList()
          ..sort((a, b) {
            if (a.completedAt == null) {
              return b.completedAt == null ? a.key.compareTo(b.key) : 1;
            }
            if (b.completedAt == null) return -1;
            return b.completedAt!.compareTo(a.completedAt!);
          });
    final undated = _records
        .where((record) => record.completedAt == null)
        .length;
    final caption = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: colors.textMuted,
    );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回答消耗概览',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text('当前主机 · 本机已记录的回答 · Token', style: caption),
              ],
            ),
            TextButton.icon(
              onPressed: _loading ? null : _reload,
              icon: const Icon(RecodexIcons.sync, size: 16),
              label: Text(_loading ? '读取中…' : '刷新统计'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            for (final entry in const {
              7: '近 7 天',
              30: '近 30 天',
              90: '近 90 天',
              365: '近一年',
              0: '全部',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _period == entry.key,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  _period = entry.key;
                  _selectedDay = null;
                  _visibleCount = 50;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {
            _selectedDay = null;
            _visibleCount = 50;
          }),
          decoration: InputDecoration(
            hintText: '筛选任务或工作区',
            prefixIcon: const Icon(RecodexIcons.search, size: 18),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除筛选',
                    icon: const Icon(RecodexIcons.close, size: 18),
                    onPressed: () => setState(() {
                      _search.clear();
                      _selectedDay = null;
                    }),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        _UsageSummary(totals: totals),
        const SizedBox(height: 10),
        Text(
          '${totals.answerCount} 次回答 · ${totals.measuredCount} 次有用量'
          '${totals.missingCount > 0 ? ' · ${totals.missingCount} 次未提供用量' : ''}',
          style: caption,
        ),
        Text('缓存包含在输入中。仅统计已同步的回答，不代表账户全部用量。', style: caption),
        if (undated > 0)
          Text('$undated 条记录缺少日期，可在“全部”明细中查看；未计入热力图。', style: caption),
        const SizedBox(height: 26),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '消耗日历',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    '${usageDateLabel(start)} — ${usageDateLabel(today)}',
                    style: caption,
                  ),
                  IconButton(
                    tooltip: '选择日期',
                    icon: const Icon(RecodexIcons.calendar, size: 18),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDay ?? today,
                        firstDate: start,
                        lastDate: today,
                      );
                      if (date != null && mounted) {
                        setState(() {
                          _selectedDay = date;
                          _visibleCount = 50;
                        });
                      }
                    },
                  ),
                ],
              ),
              if (_period == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('热力图展示最近一年，汇总和明细包含全部记录。', style: caption),
                ),
              const SizedBox(height: 12),
              UsageHeatmap(
                start: start,
                end: today,
                days: days,
                selected: _selectedDay,
                onSelected: (day) => setState(() {
                  _selectedDay = _selectedDay == day ? null : day;
                  _visibleCount = 50;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _selectedDay == null
                  ? '消耗明细'
                  : '${usageDateLabel(_selectedDay!)} 的明细',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            Text('${details.length} 次回答', style: caption),
            if (_selectedDay != null)
              TextButton(
                onPressed: () => setState(() {
                  _selectedDay = null;
                  _visibleCount = 50;
                }),
                child: const Text('清除日期'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (details.isEmpty && !_loading)
          SettingsCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _records.isEmpty ? '还没有消耗记录' : '这个范围内没有回答记录',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _records.isEmpty
                        ? '打开任务并完成回答后，消耗会记录在这里。已同步的历史回答也会自动纳入统计。'
                        : '尝试切换日期范围、清除日期或任务筛选。',
                    style: caption,
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: '消耗统计'),
        body: SettingsPageContent(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              24,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              36,
            ),
            itemCount: 2 + details.take(_visibleCount).length,
            itemBuilder: (context, index) {
              if (index == 0) return header;
              if (index <= details.take(_visibleCount).length) {
                final record = details[index - 1];
                final session = _bridge.sessions.firstWhereOrNull(
                  (session) => session.id == record.threadId,
                );
                return _UsageDetailRow(
                  record: record,
                  onOpen: session == null
                      ? null
                      : () {
                          _bridge.selectSession(session);
                          Get.offNamed(Routes.main);
                        },
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    if (details.length > _visibleCount)
                      TextButton(
                        onPressed: () => setState(() => _visibleCount += 50),
                        child: const Text('再显示 50 条'),
                      ),
                    if (_updatedAt != null)
                      Text('统计更新于 ${_timeLabel(_updatedAt!)}', style: caption),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.totals});
  final UsageTotals totals;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    Widget metric(String label, int value, int known) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: colors.textMuted)),
        const SizedBox(height: 6),
        Tooltip(
          message: known == 0
              ? '此范围未提供明细'
              : '${formatTokenCount(value)} Token · $known 次回答已提供',
          child: Text(
            known == 0 ? '—' : formatCompactTokenCount(value),
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
        ),
        if (known > 0 && known < totals.answerCount)
          Text('已知用量', style: TextStyle(fontSize: 11, color: colors.textMuted)),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        return Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            for (final child in [
              metric('总消耗', totals.totalTokens, totals.measuredCount),
              metric('输入', totals.inputTokens, totals.breakdownCount),
              metric('输出', totals.outputTokens, totals.breakdownCount),
              metric('缓存输入', totals.cachedInputTokens, totals.cachedCount),
            ])
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _UsageDetailRow extends StatelessWidget {
  const _UsageDetailRow({required this.record, this.onOpen});
  final AnswerUsageRecord record;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final usage = record.usage;
    final title = record.title.isEmpty ? '任务 ${record.threadId}' : record.title;
    final caption = TextStyle(
      fontSize: 12,
      color: colors.textMuted,
      height: 1.5,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SettingsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.completedAt == null
                            ? '时间未记录'
                            : '${usageDateLabel(record.completedAt!)} ${_timeLabel(record.completedAt!)}',
                        style: caption,
                      ),
                    ],
                  ),
                ),
                if (onOpen != null)
                  IconButton(
                    tooltip: '打开任务',
                    onPressed: onOpen,
                    icon: const Icon(RecodexIcons.chevronRight, size: 18),
                  ),
              ],
            ),
            if (record.workspace.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  record.workspace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: caption,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  usage == null
                      ? '用量未提供'
                      : '总 ${formatTokenCount(usage.totalTokens)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Text(
                  '输入 ${usage?.hasBreakdown == true ? formatTokenCount(usage!.inputTokens) : '—'}',
                  style: caption,
                ),
                Text(
                  '输出 ${usage?.hasBreakdown == true ? formatTokenCount(usage!.outputTokens) : '—'}',
                  style: caption,
                ),
                Text(
                  '缓存 ${usage?.cachedInputTokens == null ? '—' : formatTokenCount(usage!.cachedInputTokens!)}',
                  style: caption,
                ),
                if (record.durationMs != null)
                  Text(
                    '耗时 ${(record.durationMs! / 1000).toStringAsFixed(1)} 秒',
                    style: caption,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _timeLabel(DateTime value) {
  final time = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
