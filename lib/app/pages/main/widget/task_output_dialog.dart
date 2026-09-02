import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/recodex_theme.dart';

class TaskOutputDialog extends StatelessWidget {
  const TaskOutputDialog({
    required this.output,
    this.title = '任务输出',
    this.subtitle = '',
    super.key,
  });

  final String output;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 40, 760.0);
    final height = math.min(size.height - 64, 640.0);
    final hasOutput = output.trim().isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: colors.glassColor.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.glassBorder.withValues(alpha: 0.84)),
      ),
      child: SizedBox(
        width: width.clamp(280.0, 760.0),
        height: height.clamp(260.0, 640.0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(RecodexIcons.close, color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: colors.glassBorder.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: hasOutput
                    ? _TaskOutputScrollView(output: output)
                    : Center(
                        child: Text(
                          '暂无任务输出',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owns the scroll controller used by the output view and its scrollbar.
/// Keeping the same controller on both widgets avoids Scrollbar falling back
/// to the route's PrimaryScrollController before the dialog scroll view is
/// attached during its first frame.
class _TaskOutputScrollView extends StatefulWidget {
  const _TaskOutputScrollView({required this.output});

  final String output;

  @override
  State<_TaskOutputScrollView> createState() => _TaskOutputScrollViewState();
}

class _TaskOutputScrollViewState extends State<_TaskOutputScrollView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(2, 12, 8, 8),
        child: SelectableText(
          widget.output,
          style: TextStyle(
            color: colors.text,
            fontSize: 13,
            height: 1.55,
            fontFamily: 'Menlo',
            fontFamilyFallback: const [
              'SFMono-Regular',
              'PingFang SC',
              'monospace',
            ],
          ),
        ),
      ),
    );
  }
}
