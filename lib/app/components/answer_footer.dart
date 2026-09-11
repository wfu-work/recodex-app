import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/bridge_models.dart';
import '../pages/settings/theme_controller.dart';
import '../services/answer_metadata.dart';
import '../theme/recodex_theme.dart';

class AnswerFooter extends StatefulWidget {
  const AnswerFooter({
    required this.text,
    required this.showMetrics,
    this.usage,
    this.elapsed,
    this.completedAt,
    this.successful = true,
    super.key,
  });

  final String text;
  final bool showMetrics;
  final TokenUsage? usage;
  final String? elapsed;
  final DateTime? completedAt;
  final bool successful;

  @override
  State<AnswerFooter> createState() => _AnswerFooterState();
}

class _AnswerFooterState extends State<AnswerFooter> {
  Timer? _resetTimer;
  bool _copied = false;
  bool _copying = false;

  @override
  void didUpdateWidget(covariant AnswerFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _resetTimer?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copying) return;
    _copying = true;
    final text = widget.text;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || widget.text != text) return;
      _resetTimer?.cancel();
      setState(() => _copied = true);
      _resetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
    } finally {
      _copying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final scale = Get.find<ThemeController>().fontScale.value;
    final style = TextStyle(
      fontSize: 12 * scale,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
      color: colors.textMuted,
      fontWeight: FontWeight.w400,
    );
    // Give wrapped metrics a compact line height, independent of the copy
    // button's hit target. Offset the group to align its first line with it.
    final lineHeight = math.max(
      24.0,
      MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
          4,
    );
    final copyHeight = math.max(40.0, lineHeight);
    final usage = widget.usage?.scope == TokenUsageScope.turn ? widget.usage : null;
    final tokenDetail = usage == null
        ? '此回答缺少单轮用量或完整的累计记录，无法确定本次消耗'
        : [
            '本次回答用量（包含本轮所有模型调用）',
            '计量单位：Token',
            if (usage.hasBreakdown)
              '输入 ${formatTokenCount(usage.inputTokens)} · 输出 ${formatTokenCount(usage.outputTokens)}'
            else
              '输入 / 输出明细未提供',
            if (usage.cachedInputTokens != null)
              '输入中含缓存 ${formatTokenCount(usage.cachedInputTokens!)}',
            if (usage.reasoningOutputTokens != null)
              '输出中含推理 ${formatTokenCount(usage.reasoningOutputTokens!)}',
            '总消耗 ${formatTokenCount(usage.totalTokens)}',
          ].join('\n');
    final endedLabel = widget.successful ? '完成' : '结束';
    final completedAt = widget.completedAt?.toLocal();

    Widget metric(String text, {String? tooltip}) {
      final label = ConstrainedBox(
        constraints: BoxConstraints(minHeight: lineHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: Text(text, style: style),
          ),
        ),
      );
      return tooltip == null
          ? label
          : Tooltip(
              message: tooltip,
              triggerMode: TooltipTriggerMode.tap,
              child: label,
            );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            height: copyHeight,
            child: IconButton(
              key: const ValueKey('copy-answer'),
              tooltip: _copied ? '已复制' : '复制回答',
              onPressed: widget.text.isEmpty ? null : _copy,
              icon: Icon(
                _copied ? RecodexIcons.check : RecodexIcons.copy,
                size: 16,
              ),
              color: colors.textMuted,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          if (widget.showMetrics) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: (copyHeight - lineHeight) / 2),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 0,
                  children: [
                    metric(tokenUsageLabel(usage), tooltip: tokenDetail),
                    if (usage != null) ...[
                      metric(
                        '输入 ${usage.hasBreakdown ? formatCompactTokenCount(usage.inputTokens) : '未提供'}',
                        tooltip: usage.hasBreakdown
                            ? '输入 ${formatTokenCount(usage.inputTokens)} Token'
                            : null,
                      ),
                      metric(
                        '输出 ${usage.hasBreakdown ? formatCompactTokenCount(usage.outputTokens) : '未提供'}',
                        tooltip: usage.hasBreakdown
                            ? '输出 ${formatTokenCount(usage.outputTokens)} Token'
                            : null,
                      ),
                      metric(
                        '缓存 ${usage.cachedInputTokens == null ? '未提供' : formatCompactTokenCount(usage.cachedInputTokens!)}',
                        tooltip: usage.cachedInputTokens == null
                            ? '此回答的记录未提供缓存明细'
                            : '缓存 ${formatTokenCount(usage.cachedInputTokens!)} Token\n已包含在输入数量中',
                      ),
                    ],
                    metric('耗时 ${widget.elapsed ?? '未记录'}'),
                    metric(
                      completedAt == null
                          ? '$endedLabel时间未记录'
                          : '$endedLabel ${_formatDateTime(completedAt)}',
                      tooltip: completedAt == null
                          ? null
                          : '本地时间 · ${completedAt.timeZoneName}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}/${two(time.month)}/${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
