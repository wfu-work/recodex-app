import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/answer_metadata.dart';
import '../services/usage_statistics.dart';
import '../theme/recodex_theme.dart';

/// A calendar matrix: columns are weeks, rows are local weekdays. Color
/// encodes total tokens, never duration or the number of answers.
class UsageHeatmap extends StatefulWidget {
  const UsageHeatmap({
    required this.start,
    required this.end,
    required this.days,
    required this.onSelected,
    this.selected,
    super.key,
  });

  final DateTime start;
  final DateTime end;
  final Map<DateTime, UsageTotals> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  State<UsageHeatmap> createState() => _UsageHeatmapState();
}

class _UsageHeatmapState extends State<UsageHeatmap> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _showRecent();
  }

  @override
  void didUpdateWidget(UsageHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start || oldWidget.end != widget.end) {
      _showRecent();
    }
  }

  void _showRecent() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildChart);

  Widget _buildChart(BuildContext context, BoxConstraints constraints) {
    final colors = context.recodexColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = [
      colors.surfaceOverlay,
      if (dark) ...[
        const Color(0xff234832),
        const Color(0xff356b44),
        const Color(0xff4c965c),
        const Color(0xff7ac98a),
      ] else ...[
        const Color(0xffdcebdd),
        const Color(0xffa6d3ac),
        const Color(0xff67ab73),
        const Color(0xff327b45),
      ],
    ];
    final first = shiftUsageDay(widget.start, 1 - widget.start.weekday);
    final dates = <DateTime>[];
    for (
      var date = first;
      !date.isAfter(widget.end);
      date = shiftUsageDay(date, 1)
    ) {
      dates.add(date);
    }
    final weeks = (dates.length / 7).ceil();
    final maxTokens = widget.days.values.fold(
      0,
      (int max, day) => math.max(max, day.totalTokens),
    );
    final cell = constraints.maxWidth < 600
        ? 32.0
        : ((constraints.maxWidth - 30) / weeks).clamp(16.0, 32.0);
    final labelHeight = math.max(
      28.0,
      MediaQuery.textScalerOf(context).scale(13) * 1.6,
    );
    final labels = ['一', '二', '三', '四', '五', '六', '日'];
    final muted = TextStyle(fontSize: 12, color: colors.textMuted);

    Widget dayCell(DateTime date) {
      if (date.isBefore(widget.start) || date.isAfter(widget.end)) {
        return SizedBox.square(dimension: cell);
      }
      final totals = widget.days[date];
      final count = totals?.totalTokens ?? 0;
      final missing = totals?.missingCount ?? 0;
      final selected = date == widget.selected;
      final description = totals == null
          ? '${usageDateLabel(date)} · 无回答记录'
          : '${usageDateLabel(date)} · ${totals.measuredCount == 0 ? '用量未提供' : '${formatTokenCount(count)} Token'}'
                ' · ${totals.answerCount} 次回答${missing > 0 ? ' · $missing 次缺少用量' : ''}';
      return Semantics(
        label: description,
        button: true,
        selected: selected,
        onTap: () => widget.onSelected(date),
        child: Tooltip(
          message: description,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: palette[usageHeatLevel(count, maxTokens)],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(
                  color: selected ? colors.text : colors.glassBorder,
                  width: selected ? 2 : 0.6,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('usage-day-${usageDateLabel(date)}'),
                onTap: () => widget.onSelected(date),
                excludeFromSemantics: true,
                child: SizedBox.square(
                  dimension: cell - 4,
                  child: missing > 0
                      ? Center(
                          child: Icon(
                            Icons.more_horiz,
                            size: 14,
                            color:
                                usageHeatLevel(count, maxTokens) >= 3 && !dark
                                ? Colors.white
                                : colors.text,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                SizedBox(height: labelHeight),
                for (final label in labels)
                  SizedBox(
                    width: 26,
                    height: cell,
                    child: Center(child: Text(label, style: muted)),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FocusTraversalGroup(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var week = 0; week < weeks; week++)
                          Column(
                            children: [
                              SizedBox(
                                width: cell,
                                height: labelHeight,
                                child: OverflowBox(
                                  alignment: Alignment.centerLeft,
                                  maxWidth: cell * 2,
                                  child: Builder(
                                    builder: (_) {
                                      final monday = shiftUsageDay(
                                        first,
                                        week * 7,
                                      );
                                      final show =
                                          week == 0 ||
                                          monday.month !=
                                              shiftUsageDay(monday, -7).month;
                                      return show
                                          ? Text(
                                              '${(week == 0 ? widget.start : monday).month}月',
                                              style: muted,
                                            )
                                          : const SizedBox();
                                    },
                                  ),
                                ),
                              ),
                              for (var weekday = 0; weekday < 7; weekday++)
                                dayCell(
                                  shiftUsageDay(first, week * 7 + weekday),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('点击日期查看明细 · 可横向滚动', style: muted),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('少', style: muted),
                const SizedBox(width: 6),
                for (final color in palette)
                  Container(
                    width: 13,
                    height: 13,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: colors.glassBorder, width: 0.6),
                    ),
                  ),
                const SizedBox(width: 3),
                Text('多', style: muted),
              ],
            ),
            if (maxTokens > 0)
              Text(
                '最高 ${formatCompactTokenCount(maxTokens)} / 天',
                style: muted,
              ),
            if (widget.days.values.any((day) => day.missingCount > 0))
              Text('··· 表示部分用量未提供', style: muted),
          ],
        ),
      ],
    );
  }
}
