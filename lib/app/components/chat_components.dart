import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/bridge_models.dart';
import '../pages/settings/theme_controller.dart';
import '../theme/recodex_theme.dart';
import 'recodex_dropdown.dart';

class AssistantBubble extends StatelessWidget {
  const AssistantBubble({required this.event, super.key});

  final SessionEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final isUser = event.kind == 'user';
    final isError = event.kind == 'error';
    final text = _cleanEventText(event);
    final imageAttachments = event.attachments
        .where(
          (attachment) =>
              attachment.type == 'image' && attachment.dataUrl.isNotEmpty,
        )
        .toList();
    final bubbleColor = isUser
        ? colors.userBubble
        : isError
        ? colors.errorBubble
        : colors.assistantBubble;
    final borderColor = isError ? colors.errorBorder : colors.glassBorder;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: isUser ? 0.72 : 0.9,
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (imageAttachments.isNotEmpty) ...[
                  _EventImageGrid(attachments: imageAttachments),
                  if (text.isNotEmpty) const SizedBox(height: 14),
                ],
                if (text.isNotEmpty || imageAttachments.isEmpty)
                  SelectableText(
                    text.isEmpty ? '暂无输出' : text,
                    style: TextStyle(
                      fontSize: _scaledFontSize(16, fontScale),
                      height: 1.62,
                      color: isError ? colors.error : colors.text,
                      fontWeight: isUser ? FontWeight.w500 : FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventImageGrid extends StatelessWidget {
  const _EventImageGrid({required this.attachments});

  final List<EventAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final images = attachments
        .map(_EventImageData.tryParse)
        .whereType<_EventImageData>()
        .toList();
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = images.length == 1 ? 0.0 : 8.0;
        final itemWidth = images.length == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: gap,
          runSpacing: 8,
          children: [
            for (final image in images)
              _EventImageTile(image: image, width: itemWidth),
          ],
        );
      },
    );
  }
}

class _EventImageTile extends StatelessWidget {
  const _EventImageTile({required this.image, required this.width});

  final _EventImageData image;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final height = width > 260 ? 172.0 : 128.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: colors.surfaceOverlay,
        child: InkWell(
          onTap: () => _showEventImagePreview(context, image),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.glassBorder),
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: Image.memory(
                image.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      RecodexIcons.brokenImage,
                      color: colors.textMuted,
                      size: 22,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showEventImagePreview(BuildContext context, _EventImageData image) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    builder: (context) => _EventImagePreviewDialog(image: image),
  );
}

class _EventImagePreviewDialog extends StatelessWidget {
  const _EventImagePreviewDialog({required this.image});

  final _EventImageData image;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                media.padding.top + 56,
                16,
                media.padding.bottom + 34,
              ),
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Image.memory(
                      image.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: media.padding.top + 12,
            right: 16,
            child: IconButton(
              tooltip: '关闭',
              icon: const Icon(RecodexIcons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventImageData {
  const _EventImageData({required this.bytes});

  final Uint8List bytes;

  static _EventImageData? tryParse(EventAttachment attachment) {
    final dataUrl = attachment.dataUrl.trim();
    final commaIndex = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || commaIndex < 0) {
      return null;
    }
    final metadata = dataUrl.substring(0, commaIndex);
    if (!metadata.contains(';base64')) {
      return null;
    }
    try {
      return _EventImageData(
        bytes: base64Decode(dataUrl.substring(commaIndex + 1)),
      );
    } on FormatException {
      return null;
    }
  }
}

class EventTimelineItem extends StatelessWidget {
  const EventTimelineItem({required this.event, this.onUndo, super.key});

  final SessionEvent event;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    if (_isToolEvent(event.kind)) {
      final command = _extractCommand(event.text);
      return ToolCallRow(
        title: command == null ? '已运行工具' : '已运行',
        status: command ?? _shortenText(event.text, fallback: '工具调用'),
        icon: RecodexIcons.terminal,
      );
    }
    if (_isDoneEvent(event.kind)) {
      return ToolCallRow(
        title: '已处理',
        status: event.text.trim().isEmpty
            ? '完成'
            : _shortenText(event.text, fallback: '完成'),
        icon: RecodexIcons.checkCircle,
      );
    }
    if (event.kind == 'interrupted') {
      return const ToolCallRow(
        title: '已中断',
        status: '用户取消',
        icon: RecodexIcons.pause,
      );
    }
    final gitSummary = GitChangeSummary.tryParse(event.text);
    if (gitSummary != null) {
      return GitChangeCard(summary: gitSummary, onUndo: onUndo);
    }
    return AssistantBubble(event: event);
  }
}

class AssistantAnswerBlock extends StatelessWidget {
  const AssistantAnswerBlock({
    required this.events,
    required this.completed,
    this.gitChangeSummary,
    this.onGitFileTap,
    this.onUndoGitChanges,
    super.key,
  });

  final List<SessionEvent> events;
  final bool completed;
  final GitChangeSummary? gitChangeSummary;
  final ValueChanged<GitFileChange>? onGitFileTap;
  final VoidCallback? onUndoGitChanges;

  @override
  Widget build(BuildContext context) {
    final textBuffer = StringBuffer();
    final children = <Widget>[];
    final gitSummaries = <GitChangeSummary>[];
    final steps = <_AnswerStep>[];
    var hasTerminalEvent = false;
    SessionEvent? latestLiveEvent;

    void flushText() {
      final text = textBuffer.toString().trim();
      if (text.isEmpty) return;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 18));
      }
      children.add(
        _AnswerText(
          text: text,
          gitChangeSummary: gitChangeSummary,
          onFileTap: onGitFileTap,
        ),
      );
      textBuffer.clear();
    }

    void appendStep(_AnswerStep step) {
      steps.add(step);
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 7));
      }
      children.add(_AnswerStepRow(step: step));
    }

    for (final event in events) {
      if (_isDoneEvent(event.kind)) {
        hasTerminalEvent = true;
        continue;
      }
      if (event.kind == 'token_usage') {
        continue;
      }
      if (event.kind == 'running') {
        flushText();
        latestLiveEvent = event;
        continue;
      }
      if (event.kind == 'interrupted') {
        hasTerminalEvent = true;
        flushText();
        const step = _AnswerStep(
          icon: RecodexIcons.pause,
          title: '已中断',
          detail: '用户取消',
        );
        appendStep(step);
        continue;
      }
      if (_isToolEvent(event.kind)) {
        flushText();
        final step = _AnswerStep.fromToolEvent(event);
        appendStep(step);
        latestLiveEvent = event;
        continue;
      }
      final gitSummary = GitChangeSummary.tryParse(event.text);
      if (gitSummary != null) {
        flushText();
        gitSummaries.add(gitSummary);
        final step = _AnswerStep(
          icon: RecodexIcons.gitCompare,
          title: '已更新文件',
          detail: '${gitSummary.files.length} 个文件',
        );
        appendStep(step);
        continue;
      }
      final imageCount = event.attachments
          .where(
            (attachment) =>
                attachment.type == 'image' && attachment.dataUrl.isNotEmpty,
          )
          .length;
      if (imageCount > 0) {
        flushText();
        final step = _AnswerStep(
          icon: RecodexIcons.image,
          title: '已查看 $imageCount 张图像',
        );
        appendStep(step);
      }
      final text = _cleanEventText(event);
      if (text.isEmpty) continue;
      if (textBuffer.isNotEmpty && _shouldSeparateText(event.kind)) {
        textBuffer.writeln();
        textBuffer.writeln();
      }
      textBuffer.write(text);
    }
    flushText();
    final mergedGitSummary = _mergeGitSummaries(gitSummaries);
    if (mergedGitSummary != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 18));
      }
      children.add(
        _GitChangePanel(
          summary: mergedGitSummary,
          onUndo: onUndoGitChanges,
          onFileTap: onGitFileTap,
        ),
      );
    }
    if (!completed && !hasTerminalEvent) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 18));
      }
      children.add(
        latestLiveEvent == null
            ? const _LiveActivityRow(text: '正在生成回答...')
            : _LiveActivityRow.fromEvent(latestLiveEvent),
      );
    }

    final isDone = completed || hasTerminalEvent;
    if (children.isEmpty) {
      children.add(
        isDone
            ? _AnswerText(
                text: '完成。',
                gitChangeSummary: gitChangeSummary,
                onFileTap: onGitFileTap,
              )
            : const _LiveActivityRow(text: '正在思考...'),
      );
    }
    final elapsed = _elapsedLabel(events);
    final isActive = !isDone;
    final summarySteps = steps.isEmpty && isActive
        ? const [_AnswerStep(icon: RecodexIcons.reasoning, title: '正在思考')]
        : steps;

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.96,
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AnswerStatusHeader(done: isDone, elapsed: elapsed),
              const SizedBox(height: 16),
              ...children,
              if (summarySteps.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: _StepSummaryPill(
                    steps: summarySteps,
                    active: isActive,
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

class _AnswerStep {
  const _AnswerStep({required this.icon, required this.title, this.detail});

  factory _AnswerStep.fromToolEvent(SessionEvent event) {
    final command = _extractCommand(event.text);
    final raw = event.text.toLowerCase();
    final title = command != null
        ? '运行了命令'
        : raw.contains('read') ||
              raw.contains('file') ||
              raw.contains('读取') ||
              raw.contains('文件')
        ? '加载了工具读取文件'
        : '已运行工具';
    return _AnswerStep(icon: RecodexIcons.terminal, title: title);
  }

  final IconData icon;
  final String title;
  final String? detail;
}

class _AnswerStepRow extends StatelessWidget {
  const _AnswerStepRow({required this.step});

  final _AnswerStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(step.icon, size: 16, color: colors.textMuted),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            step.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: _scaledFontSize(13.5, fontScale),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if ((step.detail ?? '').trim().isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              step.detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textMuted.withValues(alpha: 0.82),
                fontSize: _scaledFontSize(13, fontScale),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepSummaryPill extends StatelessWidget {
  const _StepSummaryPill({required this.steps, required this.active});

  final List<_AnswerStep> steps;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final total = math.max(1, steps.length);
    final current = active ? math.max(1, steps.length) : total;
    final label = active ? '第 $current / $total 步' : '已完成 ${steps.length} 步';
    return Tooltip(
      message: '查看步骤',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _StepSummaryDialog(steps: steps),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceOverlay.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colors.glassBorder.withValues(alpha: 0.56),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    RecodexIcons.circle,
                    size: 15,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: _scaledFontSize(12.5, fontScale),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepSummaryDialog extends StatelessWidget {
  const _StepSummaryDialog({required this.steps});

  final List<_AnswerStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: colors.glassColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.glassBorder.withValues(alpha: 0.72)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 430),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '执行步骤',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: _scaledFontSize(16, fontScale),
                        fontWeight: FontWeight.w800,
                      ),
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
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: steps.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 13),
                  itemBuilder: (_, index) => _StepDialogRow(step: steps[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDialogRow extends StatelessWidget {
  const _StepDialogRow({required this.step});

  final _AnswerStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(RecodexIcons.circle, size: 17, color: colors.textMuted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: step.title),
                if ((step.detail ?? '').trim().isNotEmpty) ...[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: step.detail,
                    style: TextStyle(
                      color: colors.textMuted.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
            style: TextStyle(
              color: colors.textMuted,
              fontSize: _scaledFontSize(14.5, fontScale),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatingThinkingIndicator extends StatefulWidget {
  const _FloatingThinkingIndicator({this.size = 28});

  final double size;

  @override
  State<_FloatingThinkingIndicator> createState() =>
      _FloatingThinkingIndicatorState();
}

class _FloatingThinkingIndicatorState extends State<_FloatingThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      if (_reduceMotion) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    } else if (!_reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final dotSize = math.max(3.0, widget.size * 0.19);
    Widget dot(int index, double progress) {
      final phase = (progress + index * 0.17) % 1.0;
      final lift = _reduceMotion
          ? 0.0
          : -math.sin(phase * math.pi * 2) * widget.size * 0.12;
      final opacity = _reduceMotion
          ? 0.64
          : (0.44 + (math.sin(phase * math.pi * 2) + 1) * 0.22)
                .clamp(0.36, 0.90)
                .toDouble();
      return Transform.translate(
        offset: Offset(0, lift),
        child: Opacity(
          opacity: opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.textMuted,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: dotSize),
          ),
        ),
      );
    }

    Widget dots(double progress) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          dot(0, progress),
          SizedBox(width: dotSize * 0.72),
          dot(1, progress),
          SizedBox(width: dotSize * 0.72),
          dot(2, progress),
        ],
      );
    }

    Widget indicator(double progress) {
      final ringProgress = (progress + 0.28) % 1.0;
      final ringScale = _reduceMotion ? 0.74 : 0.72 + ringProgress * 0.25;
      final ringOpacity = _reduceMotion
          ? 0.24
          : (0.26 * (1 - ringProgress)).clamp(0.04, 0.26).toDouble();
      return Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: ringScale,
            child: Opacity(
              opacity: ringOpacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.textMuted, width: 1.2),
                ),
                child: SizedBox.square(dimension: widget.size),
              ),
            ),
          ),
          dots(progress),
        ],
      );
    }

    if (_reduceMotion) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: indicator(0),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => indicator(_controller.value),
      ),
    );
  }
}

class _LiveActivityRow extends StatelessWidget {
  const _LiveActivityRow({required this.text, this.detail});

  factory _LiveActivityRow.fromEvent(SessionEvent event) {
    if (_isToolEvent(event.kind)) {
      final command = _extractCommand(event.text);
      return _LiveActivityRow(
        text: command == null ? '正在运行工具' : '正在运行 ${_formatCommand(command)}',
        detail: '正在思考',
      );
    }
    final text = event.text.trim().isEmpty ? '正在思考...' : event.text.trim();
    return _LiveActivityRow(text: text);
  }

  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _FloatingThinkingIndicator(size: 28),
          const SizedBox(width: 4),
          Icon(RecodexIcons.terminal, size: 17, color: colors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text.withValues(alpha: 0.92),
                fontSize: _scaledFontSize(15, fontScale),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if ((detail ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(13, fontScale),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerStatusHeader extends StatelessWidget {
  const _AnswerStatusHeader({required this.done, required this.elapsed});

  final bool done;
  final String? elapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final label = done
        ? elapsed == null
              ? '已处理'
              : '已处理 $elapsed'
        : elapsed == null
        ? '正在处理'
        : '正在处理 $elapsed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.16)),
      ],
    );
  }
}

class _AnswerText extends StatelessWidget {
  const _AnswerText({
    required this.text,
    this.gitChangeSummary,
    this.onFileTap,
  });

  final String text;
  final GitChangeSummary? gitChangeSummary;
  final ValueChanged<GitFileChange>? onFileTap;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    var inModifiedFiles = false;
    final modifiedFiles = <_ModifiedFileReference>[];

    void flushModifiedFiles() {
      if (modifiedFiles.isEmpty) return;
      widgets.add(
        _ModifiedFilesBlock(
          files: List<_ModifiedFileReference>.of(modifiedFiles),
          onFileTap: onFileTap,
        ),
      );
      modifiedFiles.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        flushModifiedFiles();
        inModifiedFiles = false;
        widgets.add(const SizedBox(height: 12));
        continue;
      }

      if (_isModifiedFilesHeader(line)) {
        flushModifiedFiles();
        inModifiedFiles = true;
        continue;
      }

      final file = inModifiedFiles ? _extractFileReference(line) : null;
      if (file != null) {
        modifiedFiles.add(_withGitDelta(file, gitChangeSummary));
        continue;
      }

      flushModifiedFiles();
      inModifiedFiles = false;
      widgets.add(_AnswerLine(text: line));
    }
    flushModifiedFiles();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final trimmed = text.trimLeft();
    final isBullet = trimmed.startsWith('- ') || trimmed.startsWith('• ');
    final isHeading =
        !isBullet &&
        trimmed.length <= 18 &&
        !trimmed.contains(RegExp(r'[。.:：]'));
    final content = isBullet ? trimmed.substring(2).trimLeft() : text;
    final richText = Text.rich(
      TextSpan(children: _inlineSpans(context, content)),
      style: TextStyle(
        color: colors.text,
        fontSize: _scaledFontSize(isHeading ? 16.5 : 15.5, fontScale),
        height: 1.62,
        fontWeight: isHeading ? FontWeight.w600 : FontWeight.w400,
        letterSpacing: 0,
      ),
    );

    if (!isBullet) {
      return Padding(
        padding: EdgeInsets.only(bottom: isHeading ? 8 : 6),
        child: richText,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(
              RecodexIcons.circle,
              size: 5.5,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: richText),
        ],
      ),
    );
  }
}

class _ModifiedFileReference {
  const _ModifiedFileReference({required this.path, this.added, this.removed});

  final String path;
  final int? added;
  final int? removed;

  GitFileChange toGitFileChange() {
    return GitFileChange(path: path, added: added ?? 0, removed: removed ?? 0);
  }
}

class _ModifiedFilesBlock extends StatelessWidget {
  const _ModifiedFilesBlock({required this.files, this.onFileTap});

  final List<_ModifiedFileReference> files;
  final ValueChanged<GitFileChange>? onFileTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final added = files.fold<int>(0, (sum, file) => sum + (file.added ?? 0));
    final removed = files.fold<int>(
      0,
      (sum, file) => sum + (file.removed ?? 0),
    );
    final hasDelta = files.any(
      (file) => file.added != null || file.removed != null,
    );
    final rowDivider = colors.textMuted.withValues(alpha: isDark ? 0.14 : 0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xff171717).withValues(alpha: 0.86)
              : colors.assistantBubble.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.glassBorder.withValues(alpha: 0.92)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${files.length} 个文件'),
                          if (hasDelta) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: '+$added',
                              style: TextStyle(color: colors.success),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(
                              text: '-$removed',
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: _scaledFontSize(16, fontScale),
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                  Icon(
                    RecodexIcons.chevronDown,
                    size: 22,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: rowDivider),
            for (var index = 0; index < files.length; index++) ...[
              _ModifiedFileBlockRow(
                file: files[index],
                onTap: onFileTap == null
                    ? null
                    : () => onFileTap!(files[index].toGitFileChange()),
              ),
              if (index != files.length - 1)
                Divider(height: 1, color: rowDivider),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModifiedFileBlockRow extends StatelessWidget {
  const _ModifiedFileBlockRow({required this.file, this.onTap});

  final _ModifiedFileReference file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final hasDelta = file.added != null || file.removed != null;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: _baseName(file.path)),
                  if (hasDelta) ...[
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: '+${file.added ?? 0}',
                      style: TextStyle(color: colors.success),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: '-${file.removed ?? 0}',
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: _scaledFontSize(15.5, fontScale),
                fontWeight: FontWeight.w600,
                height: 1.12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(RecodexIcons.chevronDown, size: 22, color: colors.textMuted),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    required this.title,
    required this.status,
    this.icon = RecodexIcons.checkCircle,
    this.onTap,
    super.key,
  });

  final String title;
  final String status;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: colors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: _scaledFontSize(14, fontScale),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              status,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: content,
          ),
        ),
      ),
    );
  }
}

class GitChangeCard extends StatelessWidget {
  const GitChangeCard({
    required this.summary,
    this.onUndo,
    this.onFileTap,
    super.key,
  });

  final GitChangeSummary summary;
  final VoidCallback? onUndo;
  final ValueChanged<GitFileChange>? onFileTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.centerLeft,
        child: _GitChangePanel(
          summary: summary,
          onUndo: onUndo,
          onFileTap: onFileTap,
        ),
      ),
    );
  }
}

class _GitChangePanel extends StatelessWidget {
  const _GitChangePanel({required this.summary, this.onUndo, this.onFileTap});

  final GitChangeSummary summary;
  final VoidCallback? onUndo;
  final ValueChanged<GitFileChange>? onFileTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = isDark
        ? const Color(0xff171717).withValues(alpha: 0.86)
        : colors.assistantBubble.withValues(alpha: 0.78);
    final rowDivider = colors.textMuted.withValues(alpha: isDark ? 0.14 : 0.12);
    final fileCountLabel = '已编辑 ${summary.files.length} 个文件';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.glassBorder.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(alpha: isDark ? 0.26 : 0.10),
            offset: const Offset(0, 14),
            blurRadius: 30,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Icon(RecodexIcons.gitCompare, size: 21, color: colors.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          fileCountLabel,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: _scaledFontSize(16, fontScale),
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _DeltaText(
                          added: summary.added,
                          removed: summary.removed,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (onUndo != null)
                  _GitActionButton(
                    icon: RecodexIcons.undo,
                    tooltip: '撤销',
                    onPressed: onUndo,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: rowDivider),
          for (var index = 0; index < summary.files.length; index++) ...[
            _GitFileRow(
              file: summary.files[index],
              onTap: onFileTap == null
                  ? null
                  : () => onFileTap!(summary.files[index]),
            ),
            if (index != summary.files.length - 1)
              Divider(height: 1, color: rowDivider),
          ],
        ],
      ),
    );
  }
}

class GitChangeSummary {
  const GitChangeSummary({
    required this.files,
    required this.added,
    required this.removed,
  });

  final List<GitFileChange> files;
  final int added;
  final int removed;

  static GitChangeSummary? tryParse(String raw) {
    final files = <GitFileChange>[];
    var totalAdded = 0;
    var totalRemoved = 0;
    if (raw.contains('\t')) {
      for (final line in raw.split('\n')) {
        final parts = line.split('\t');
        if (parts.length < 3) continue;
        final added = int.tryParse(parts[0]) ?? 0;
        final removed = int.tryParse(parts[1]) ?? 0;
        final path = parts.sublist(2).join('\t').trim();
        if (path.isEmpty) continue;
        totalAdded += added;
        totalRemoved += removed;
        files.add(GitFileChange(path: path, added: added, removed: removed));
      }
      if (files.isNotEmpty) {
        return GitChangeSummary(
          files: files,
          added: totalAdded,
          removed: totalRemoved,
        );
      }
    }
    for (final line in raw.split('\n')) {
      final match = RegExp(
        r'^\s*(.+?)\s+\|\s+\d+\s+([+\-]+)\s*$',
      ).firstMatch(line);
      if (match == null) continue;
      final path = match.group(1)?.trim() ?? '';
      final graph = match.group(2) ?? '';
      if (path.isEmpty) continue;
      final added = '+'.allMatches(graph).length;
      final removed = '-'.allMatches(graph).length;
      totalAdded += added;
      totalRemoved += removed;
      files.add(GitFileChange(path: path, added: added, removed: removed));
    }
    if (files.isEmpty) return null;
    return GitChangeSummary(
      files: files,
      added: totalAdded,
      removed: totalRemoved,
    );
  }
}

GitChangeSummary? _mergeGitSummaries(List<GitChangeSummary> summaries) {
  if (summaries.isEmpty) return null;
  final filesByPath = <String, GitFileChange>{};
  for (final summary in summaries) {
    for (final file in summary.files) {
      final key = _normalizePath(file.path);
      final existing = filesByPath[key];
      filesByPath[key] = GitFileChange(
        path: existing?.path ?? file.path,
        added: (existing?.added ?? 0) + file.added,
        removed: (existing?.removed ?? 0) + file.removed,
      );
    }
  }
  final files = filesByPath.values.toList()
    ..sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));
  if (files.isEmpty) return null;
  return GitChangeSummary(
    files: files,
    added: files.fold<int>(0, (sum, file) => sum + file.added),
    removed: files.fold<int>(0, (sum, file) => sum + file.removed),
  );
}

class _GitActionButton extends StatelessWidget {
  const _GitActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: colors.textMuted,
        disabledColor: colors.textMuted.withValues(alpha: 0.36),
      ),
    );
  }
}

class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.added,
    required this.removed,
  });

  final String path;
  final int added;
  final int removed;
}

class _GitFileRow extends StatelessWidget {
  const _GitFileRow({required this.file, this.onTap});

  final GitFileChange file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final fileName = _baseName(file.path);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            RecodexIcons.fileText,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                fileName.isEmpty ? file.path : fileName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: _scaledFontSize(15.5, fontScale),
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _DeltaText(added: file.added, removed: file.removed),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _DeltaText extends StatelessWidget {
  const _DeltaText({required this.added, required this.removed});

  final int added;
  final int removed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+$added',
            style: TextStyle(color: colors.success),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '-$removed',
            style: TextStyle(color: colors.error),
          ),
        ],
      ),
      style: TextStyle(
        fontSize: _scaledFontSize(14, fontScale),
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class ComposerBar extends StatelessWidget {
  const ComposerBar({
    required this.controller,
    required this.enabled,
    required this.context,
    required this.permissionMode,
    required this.onSend,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onPermissionModeChanged,
    required this.onVoicePressed,
    this.running = false,
    this.onStop,
    this.listening = false,
    super.key,
  });

  static const List<String> permissionModes = ['默认权限', '自动审查', '完全访问权限'];

  final TextEditingController controller;
  final bool enabled;
  final ComposerContext context;
  final String permissionMode;
  final VoidCallback onSend;
  final bool running;
  final VoidCallback? onStop;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onPermissionModeChanged;
  final VoidCallback onVoicePressed;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ComposerGlassPanel(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          radius: 32,
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: colors.glassBorder.withValues(
                      alpha: isDark ? 0.24 : 0.72,
                    ),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  enabled: enabled && !running,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask anything... @files, \$skills, /commands',
                    hintStyle: TextStyle(
                      color: colors.textMuted.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ComposerIconButton(
                    icon: RecodexIcons.add,
                    onPressed: enabled ? () {} : null,
                  ),
                  if (running) ...[
                    const SizedBox(width: 6),
                    _PermissionModePill(
                      icon: RecodexIcons.shield,
                      value: permissionMode,
                      values: permissionModes,
                      onChanged: onPermissionModeChanged,
                    ),
                    const Spacer(),
                    const _FloatingThinkingIndicator(size: 24),
                    const SizedBox(width: 4),
                    Flexible(child: _RunningModelLabel(context: this.context)),
                  ] else ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ComposerMenuButton(
                              icon: RecodexIcons.fast,
                              label: this.context.model,
                              values: this.context.models,
                              labelForValue: this.context.modelLabel,
                              onChanged: onModelChanged,
                            ),
                            const SizedBox(width: 6),
                            _ComposerMenuButton(
                              icon: RecodexIcons.reasoning,
                              label: _reasoningLabel(
                                this.context.reasoningEffort,
                              ),
                              values: this.context.reasoningEfforts,
                              labelForValue: _reasoningLabel,
                              onChanged: onReasoningChanged,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ComposerIconButton(
                      icon: RecodexIcons.mic,
                      active: listening,
                      onPressed: enabled ? onVoicePressed : null,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Tooltip(
                    message: running ? '停止任务' : '发送消息',
                    child: SizedBox.square(
                      dimension: 48,
                      child: FilledButton(
                        onPressed: running
                            ? onStop
                            : enabled
                            ? onSend
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: running ? colors.text : colors.text,
                          foregroundColor: running
                              ? (isDark
                                    ? colors.glassColor
                                    : colors.surfaceOverlay)
                              : (isDark
                                    ? colors.glassColor
                                    : colors.glassHighlight),
                          disabledBackgroundColor: colors.textMuted.withValues(
                            alpha: 0.34,
                          ),
                          disabledForegroundColor: colors.textMuted,
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          elevation: 0,
                        ),
                        child: Icon(
                          running ? RecodexIcons.stop : RecodexIcons.arrowUp,
                          size: running ? 20 : 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!running) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ContextMenuPill(
                  icon: RecodexIcons.laptop,
                  label: this.context.transport,
                  items: [
                    _ContextMenuItem(
                      icon: RecodexIcons.laptop,
                      title: this.context.transport,
                      subtitle: '本机 Bridge 上下文',
                    ),
                    _ContextMenuItem(
                      icon: RecodexIcons.accountTree,
                      title: this.context.branch.isEmpty
                          ? '未读取分支'
                          : this.context.branch,
                      subtitle: '当前 Git 分支',
                    ),
                    _ContextMenuItem(
                      icon: RecodexIcons.shield,
                      title: this.context.requireConfirmGitWrite
                          ? 'Git 写操作需确认'
                          : '信任当前工作区',
                      subtitle: '权限策略',
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                _PermissionModePill(
                  icon: RecodexIcons.shield,
                  value: permissionMode,
                  values: permissionModes,
                  onChanged: onPermissionModeChanged,
                ),
                const SizedBox(width: 18),
                _ContextPill(
                  icon: RecodexIcons.accountTree,
                  label: this.context.branch.isEmpty
                      ? 'branch'
                      : this.context.branch,
                ),
                const SizedBox(width: 10),
                _ContextPill(
                  icon: RecodexIcons.cloudDone,
                  label: this.context.approvalPolicy,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RunningModelLabel extends StatelessWidget {
  const _RunningModelLabel({required this.context});

  final ComposerContext context;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final model = this.context.model.trim().isEmpty
        ? 'Codex'
        : this.context.modelLabel(this.context.model);
    final reasoning = _reasoningLabel(this.context.reasoningEffort);
    return Text(
      '$model  $reasoning',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ComposerGlassPanel extends StatelessWidget {
  const _ComposerGlassPanel({
    required this.child,
    required this.padding,
    required this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(alpha: isDark ? 0.34 : 0.12),
            offset: const Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          color: colors.glassColor,
          border: Border.all(color: colors.glassBorder, width: 1),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: active
          ? context.recodexColors.icon
          : context.recodexColors.textMuted,
      iconSize: 24,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(42, 42),
      ),
    );
  }
}

class _ComposerMenuButton extends StatelessWidget {
  const _ComposerMenuButton({
    required this.icon,
    required this.label,
    required this.values,
    required this.onChanged,
    this.labelForValue,
  });

  final IconData icon;
  final String label;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final String Function(String value)? labelForValue;

  @override
  Widget build(BuildContext context) {
    final selected = values.firstWhere(
      (value) =>
          value == label || (labelForValue?.call(value) ?? value) == label,
      orElse: () => values.isEmpty ? '' : values.first,
    );
    return RecodexDropdown<String>(
      value: selected,
      options: values
          .map(
            (value) => RecodexDropdownOption<String>(
              value: value,
              label: labelForValue?.call(value) ?? value,
            ),
          )
          .toList(),
      leadingIcon: icon,
      maxWidth: 168,
      compact: true,
      tooltip: '选择$label',
      onChanged: onChanged,
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = colors.textMuted;
    final background = isDark
        ? colors.glassColor.withValues(alpha: 0.44)
        : Colors.white.withValues(alpha: 0.62);
    final border = isDark
        ? colors.glassBorder.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.76);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: foreground),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 2),
              Icon(trailing, size: 17, color: foreground),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionModePill extends StatelessWidget {
  const _PermissionModePill({
    required this.icon,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final IconData icon;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = values.contains(value) ? value : values.first;
    return RecodexDropdown<String>(
      value: selected,
      options: values
          .map(
            (item) => RecodexDropdownOption<String>(value: item, label: item),
          )
          .toList(),
      leadingIcon: icon,
      warningWhen: (item) => item == '完全访问权限',
      tooltip: '选择权限模式',
      onChanged: onChanged,
    );
  }
}

class _ContextMenuPill extends StatelessWidget {
  const _ContextMenuPill({
    required this.icon,
    required this.label,
    required this.items,
  });

  final IconData icon;
  final String label;
  final List<_ContextMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return RecodexPopupMenuButton<int>(
      itemBuilder: (context) => [
        for (var index = 0; index < items.length; index += 1)
          PopupMenuItem<int>(
            value: index,
            enabled: false,
            child: _ContextMenuItemView(item: items[index]),
          ),
      ],
      child: _ContextPill(
        icon: icon,
        label: label,
        trailing: RecodexIcons.chevronDown,
      ),
    );
  }
}

class _ContextMenuItem {
  const _ContextMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _ContextMenuItemView extends StatelessWidget {
  const _ContextMenuItemView({required this.item});

  final _ContextMenuItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(item.icon, size: 19, color: context.recodexColors.textMuted),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: const TextStyle(
                color: Color(0xff303132),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitle,
              style: const TextStyle(
                color: Color(0xff747878),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _reasoningLabel(String value) {
  return switch (value) {
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    _ => value,
  };
}

double _scaledFontSize(double baseSize, double fontScale) {
  return baseSize * fontScale;
}

List<InlineSpan> _inlineSpans(BuildContext context, String text) {
  final colors = context.recodexColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final spans = <InlineSpan>[];
  final matches = RegExp(
    r'\[([^\]]+)\]\(((?:/|[A-Za-z]:\\)[^)]+)\)|`([^`]+)`|((?:/|[A-Za-z]:\\)[^\s，。；、]+(?::\d+)?)',
  ).allMatches(text).toList();
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final markdownLabel = match.group(1);
    final markdownTarget = match.group(2);
    if (markdownTarget != null) {
      spans.add(_fileLinkSpan(context, markdownTarget, markdownLabel));
      cursor = match.end;
      continue;
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xff1f2023).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            match.group(3) ?? match.group(4) ?? '',
            style: TextStyle(
              color: colors.text,
              fontFamily: 'Menlo',
              fontFamilyFallback: const [
                'SF Mono',
                'Monaco',
                'Consolas',
                'monospace',
              ],
              fontSize: 14.5,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}

InlineSpan _fileLinkSpan(BuildContext context, String target, String? label) {
  final color = Theme.of(context).colorScheme.primary;
  final parsed = _parseFileLinkTarget(target);
  final fallbackName = _baseName(parsed.path);
  final labelName = (label ?? '').trim();
  final fileName = labelName.isEmpty || labelName.startsWith('/')
      ? fallbackName
      : labelName;
  final suffix = parsed.line == null ? '' : ' (line ${parsed.line})';
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(RecodexIcons.fileText, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$fileName$suffix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ],
      ),
    ),
  );
}

({String path, String? line}) _parseFileLinkTarget(String target) {
  final trimmed = target.trim();
  final match = RegExp(r'^(.*):(\d+)$').firstMatch(trimmed);
  if (match == null) return (path: trimmed, line: null);
  return (path: match.group(1) ?? trimmed, line: match.group(2));
}

bool _isModifiedFilesHeader(String line) {
  final text = line.trim();
  return text == '修改在:' ||
      text == '修改在：' ||
      text == '修改文件:' ||
      text == '修改文件：' ||
      text == '修改的文件:' ||
      text == '修改的文件：';
}

_ModifiedFileReference? _extractFileReference(String line) {
  final trimmed = line.trim();
  final content = (trimmed.startsWith('- ') || trimmed.startsWith('• '))
      ? trimmed.substring(2).trim()
      : trimmed;
  final added = int.tryParse(
    RegExp(r'\+(\d+)').firstMatch(content)?.group(1) ?? '',
  );
  final removed = int.tryParse(
    RegExp(r'-(\d+)').firstMatch(content)?.group(1) ?? '',
  );
  final markdown = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)').firstMatch(content);
  if (markdown != null) {
    final path = markdown.group(1) ?? markdown.group(2) ?? '';
    if (path.trim().isEmpty) return null;
    return _ModifiedFileReference(path: path, added: added, removed: removed);
  }
  final path = RegExp(r'([^\s`]+\.dart)\b').firstMatch(content);
  final value = path?.group(1);
  if (value == null || value.trim().isEmpty) return null;
  return _ModifiedFileReference(path: value, added: added, removed: removed);
}

_ModifiedFileReference _withGitDelta(
  _ModifiedFileReference file,
  GitChangeSummary? summary,
) {
  if (file.added != null && file.removed != null) return file;
  if (summary == null) return file;
  final normalizedPath = _normalizePath(file.path);
  final normalizedName = _baseName(normalizedPath);
  for (final change in summary.files) {
    final changePath = _normalizePath(change.path);
    if (changePath == normalizedPath ||
        _baseName(changePath) == normalizedName) {
      return _ModifiedFileReference(
        path: file.path,
        added: file.added ?? change.added,
        removed: file.removed ?? change.removed,
      );
    }
  }
  return file;
}

String _baseName(String path) {
  final normalized = _normalizePath(path);
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/').trim();
}

bool _isToolEvent(String kind) {
  final normalized = kind.toLowerCase();
  return normalized == 'tool' ||
      normalized.contains('exec') ||
      normalized.contains('function_call') ||
      normalized.contains('shell') ||
      normalized.contains('command') ||
      normalized.contains('mcp_tool') ||
      normalized.contains('tool');
}

bool _isDoneEvent(String kind) {
  final normalized = kind.toLowerCase();
  return normalized == 'done' ||
      normalized.contains('complete') ||
      normalized.contains('completed');
}

bool _shouldSeparateText(String kind) {
  final normalized = kind.toLowerCase();
  return !normalized.contains('delta');
}

String? _elapsedLabel(List<SessionEvent> events) {
  final times = events
      .map((event) => event.time)
      .whereType<DateTime>()
      .toList(growable: false);
  if (times.length < 2) return null;
  final elapsed = times.last.difference(times.first);
  if (elapsed.isNegative) return null;
  final seconds = elapsed.inSeconds;
  if (seconds < 1) return '少于 1 秒';
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes == 0) return '$remainingSeconds 秒';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) {
    if (remainingSeconds == 0) return '$minutes 分钟';
    return '$minutes 分 $remainingSeconds 秒';
  }
  if (remainingMinutes == 0) return '$hours 小时';
  return '$hours 小时 $remainingMinutes 分';
}

String _cleanEventText(SessionEvent event) {
  final text = event.text.trim();
  if (event.kind == 'user') return _cleanUserPrompt(text);
  if (_isDoneEvent(event.kind) && text.isEmpty) return '完成。';
  return text;
}

String _cleanUserPrompt(String text) {
  const marker = '## My request for Codex:';
  final markerIndex = text.indexOf(marker);
  if (markerIndex >= 0) {
    return text.substring(markerIndex + marker.length).trim();
  }

  final lines = text.split('\n');
  final usefulLines = <String>[];
  var skippingIdeContext = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed == '# Context from my IDE setup:') {
      skippingIdeContext = true;
      continue;
    }
    if (skippingIdeContext) {
      if (trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('- ')) continue;
      if (trimmed.isEmpty) continue;
      skippingIdeContext = false;
    }
    usefulLines.add(line);
  }
  return usefulLines.join('\n').trim();
}

String? _extractCommand(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final codeMatch = RegExp(r'`([^`]+)`').firstMatch(text);
  if (codeMatch != null) return codeMatch.group(1);
  final commandMatch = RegExp(
    r'(?:(?:cmd|command|命令)\s*[:：]\s*)(.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  return commandMatch?.group(1)?.trim();
}

String _formatCommand(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) return '工具';
  final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 34) return normalized;
  return '${normalized.substring(0, 34)}...';
}

String _shortenText(String text, {required String fallback}) {
  final oneLine = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (oneLine.isEmpty) return fallback;
  return oneLine.length <= 36 ? oneLine : '${oneLine.substring(0, 36)}...';
}
