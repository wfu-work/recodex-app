import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/markdown_table.dart';
import '../theme/recodex_theme.dart';

/// A readable answer table that scrolls within the transcript on narrow screens.
class AnswerTable extends StatefulWidget {
  const AnswerTable({
    required this.table,
    required this.inlineSpans,
    this.fontScale = 1,
    super.key,
  });

  final MarkdownTable table;
  final List<InlineSpan> Function(BuildContext, String) inlineSpans;
  final double fontScale;

  @override
  State<AnswerTable> createState() => _AnswerTableState();
}

class _AnswerTableState extends State<AnswerTable> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final style = TextStyle(
      color: colors.text,
      fontSize: 14.5 * widget.fontScale,
      height: 1.5,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 640.0;
          final widths = _columnWidths(context, style, available);
          final naturalWidth = widths.fold(0.0, (sum, width) => sum + width);
          final scrolls = naturalWidth > available;
          final tableWidth = math.max(naturalWidth, available);
          final radius = BorderRadius.circular(10);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.glassBorder),
                  borderRadius: radius,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: SelectionArea(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: scrolls,
                      thickness: 3,
                      radius: const Radius.circular(3),
                      child: SingleChildScrollView(
                        key: const ValueKey('answer-table-horizontal-scroll'),
                        controller: _scrollController,
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.only(bottom: scrolls ? 8 : 0),
                        child: SizedBox(
                          width: tableWidth,
                          child: Table(
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.top,
                            columnWidths: {
                              for (
                                var column = 0;
                                column < widths.length;
                                column++
                              )
                                column: FixedColumnWidth(
                                  widths[column] * tableWidth / naturalWidth,
                                ),
                            },
                            border: TableBorder(
                              horizontalInside: BorderSide(
                                color: colors.glassBorder,
                              ),
                            ),
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                  color: colors.surfaceOverlay.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                                children: [
                                  for (
                                    var column = 0;
                                    column < widths.length;
                                    column++
                                  )
                                    _cell(
                                      context,
                                      widget.table.headers[column],
                                      column,
                                      style,
                                      header: true,
                                    ),
                                ],
                              ),
                              for (final row in widget.table.rows)
                                TableRow(
                                  children: [
                                    for (
                                      var column = 0;
                                      column < widths.length;
                                      column++
                                    )
                                      _cell(
                                        context,
                                        row[column],
                                        column,
                                        style,
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (scrolls)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '左右滑动查看完整表格',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11.5 * widget.fontScale,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String text,
    int column,
    TextStyle style, {
    bool header = false,
  }) {
    final alignment = switch (widget.table.alignments[column]) {
      MarkdownTableAlignment.left => TextAlign.left,
      MarkdownTableAlignment.center => TextAlign.center,
      MarkdownTableAlignment.right => TextAlign.right,
    };
    return Semantics(
      header: header,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text.rich(
          TextSpan(children: widget.inlineSpans(context, text)),
          textAlign: alignment,
          style: header ? style.copyWith(fontWeight: FontWeight.w600) : style,
        ),
      ),
    );
  }

  List<double> _columnWidths(
    BuildContext context,
    TextStyle style,
    double available,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    final measuredStyle = DefaultTextStyle.of(context).style.merge(style);
    final scale = textScaler.scale(style.fontSize!) / 14.5;
    final maxWidth = (available < 600 ? 240.0 : 320.0) * scale;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    );
    final rows = [widget.table.headers, ...widget.table.rows];
    try {
      return List.generate(widget.table.headers.length, (column) {
        var width = 88.0 * scale;
        for (final row in rows) {
          // Measure plain labels, not Markdown punctuation or link targets.
          final text = row[column]
              .replaceAllMapped(
                RegExp(r'\[([^\]]+)\]\([^)]+\)'),
                (match) => match[1]!,
              )
              .replaceAll(RegExp(r'[`*]'), '');
          painter.text = TextSpan(
            text: text,
            style: measuredStyle.copyWith(fontWeight: FontWeight.w600),
          );
          painter.layout();
          width = math.max(width, painter.width + 28);
          if (width >= maxWidth) break;
        }
        return width.clamp(88.0 * scale, maxWidth);
      });
    } finally {
      painter.dispose();
    }
  }
}
