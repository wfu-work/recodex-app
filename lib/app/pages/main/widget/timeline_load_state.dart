import 'package:flutter/material.dart';

import '../../../components/liquid_glass.dart';
import '../../../theme/recodex_theme.dart';

/// A compact, in-context status card for loading a selected task transcript.
/// It makes the wait measurable and gives the user a recovery action when the
/// Relay or host does not answer.
class TimelineLoadState extends StatelessWidget {
  const TimelineLoadState({
    required this.loading,
    required this.elapsedSeconds,
    required this.error,
    required this.onRetry,
    this.cardRadius = 24,
    super.key,
  });

  final bool loading;
  final int elapsedSeconds;
  final String error;
  final VoidCallback onRetry;
  final double cardRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final hasError = error.trim().isNotEmpty;
    final iconColor = hasError ? colors.error : colors.textMuted;
    final title = loading
        ? '正在加载任务对话'
        : hasError
        ? '任务对话加载失败'
        : '任务暂无可展示内容';
    final detail = loading
        ? '已等待 ${elapsedSeconds.clamp(0, 999999)} 秒 · 首次加载通常需要几秒'
        : hasError
        ? error
        : '目标主机返回了空的任务记录，可以重新加载试试。';

    return Align(
      // Keep the first-load state balanced in the available conversation
      // area. The content width remains fluid, but it should not hug the
      // leading edge while the rest of the workbench is still empty.
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.center,
        child: LiquidGlass(
          radius: cardRadius,
          opacity: 0.72,
          padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textMuted,
                        ),
                      )
                    : Icon(
                        hasError ? RecodexIcons.warning : RecodexIcons.info,
                        size: 19,
                        color: iconColor,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: TextStyle(
                        color: hasError ? colors.error : colors.textMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (!loading) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.text,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(RecodexIcons.sync, size: 16),
                          label: const Text('重新加载'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
