import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
import '../services/answer_metadata.dart';
import '../theme/recodex_theme.dart';

/// A determinate, quiet ring; tapping or hovering reveals the current context.
class ContextWindowIndicator extends StatefulWidget {
  const ContextWindowIndicator({required this.usage, super.key});

  final ContextWindowUsage usage;

  @override
  State<ContextWindowIndicator> createState() => _ContextWindowIndicatorState();
}

class _ContextWindowIndicatorState extends State<ContextWindowIndicator> {
  final _tooltipKey = GlobalKey<TooltipState>();

  void _showDetails() => _tooltipKey.currentState?.ensureTooltipVisible();

  @override
  Widget build(BuildContext context) {
    final usage = widget.usage;
    final colors = context.recodexColors;
    final description =
        '上下文窗口\n${usage.percent}% 已用\n'
        '已用 ${formatCompactTokenCount(usage.usedTokens)} / '
        '共 ${formatCompactTokenCount(usage.maxTokens)} Token';
    return Tooltip(
      key: _tooltipKey,
      message: description,
      preferBelow: false,
      triggerMode: TooltipTriggerMode.manual,
      showDuration: const Duration(seconds: 5),
      waitDuration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textAlign: TextAlign.center,
      textStyle: TextStyle(color: colors.text, fontSize: 13, height: 1.5),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.glassBorder),
      ),
      excludeFromSemantics: true,
      child: Semantics(
        label:
            '上下文窗口，${usage.percent}% 已用，'
            '已用 ${formatTokenCount(usage.usedTokens)}，'
            '共 ${formatTokenCount(usage.maxTokens)} Token',
        button: true,
        onTap: _showDetails,
        child: ExcludeSemantics(
          child: IconButton(
            onPressed: _showDetails,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.all(13),
            ),
            icon: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                value: usage.fraction,
                strokeWidth: 2.5,
                strokeCap: StrokeCap.round,
                backgroundColor: colors.textMuted.withValues(alpha: 0.2),
                color: colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
