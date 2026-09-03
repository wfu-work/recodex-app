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
  const AssistantBubble({
    required this.event,
    this.cardRadius = 24,
    this.userMessageMaxWidth = 760,
    super.key,
  });

  final SessionEvent event;
  final double cardRadius;
  final double userMessageMaxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final isUser = event.kind == 'user';
    final isError = event.kind == 'error';
    final text = _cleanEventText(event);
    final imageAttachments = event.attachments
        .where(_isRenderableImageAttachment)
        .toList();

    // Codex renders a user's attachments and message as two separate pieces:
    // a compact thumbnail strip followed by a neutral text pill. Keeping that
    // structure here also prevents a single screenshot from expanding into a
    // large, answer-like card.
    if (isUser) {
      return _UserMessageContent(
        text: text,
        attachments: imageAttachments,
        fontScale: fontScale,
        cardRadius: cardRadius,
        maxWidth: userMessageMaxWidth,
      );
    }

    final bubbleColor = isError ? colors.errorBubble : colors.assistantBubble;
    final borderColor = isError ? colors.errorBorder : colors.glassBorder;

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(
              _conversationCardRadius(cardRadius),
            ),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      height: 1.55,
                      color: isError ? colors.error : colors.text,
                      fontWeight: FontWeight.w400,
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

class _UserMessageContent extends StatelessWidget {
  const _UserMessageContent({
    required this.text,
    required this.attachments,
    required this.fontScale,
    required this.cardRadius,
    required this.maxWidth,
  });

  final String text;
  final List<EventAttachment> attachments;
  final double fontScale;
  final double cardRadius;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The conversation pane can be much wider than its readable content
        // column on desktop. Do not use the window width here: long prompts
        // should remain recognizably separate from the assistant answer,
        // instead of turning into a full-width horizontal band.
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final effectiveMaxWidth = math.min(maxWidth, availableWidth);
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachments.isNotEmpty)
                  _UserImageStrip(attachments: attachments),
                if (attachments.isNotEmpty && text.isNotEmpty)
                  const SizedBox(height: 8),
                if (text.isNotEmpty)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.userBubble,
                      borderRadius: BorderRadius.circular(
                        _conversationCardRadius(cardRadius),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: SelectableText(
                        text,
                        style: TextStyle(
                          fontSize: _scaledFontSize(16, fontScale),
                          height: 1.55,
                          color: colors.text,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                if (text.isEmpty && attachments.isEmpty)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.userBubble,
                      borderRadius: BorderRadius.circular(
                        _conversationCardRadius(cardRadius),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: SelectableText('暂无输出'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UserImageStrip extends StatelessWidget {
  const _UserImageStrip({required this.attachments});

  final List<EventAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final images = attachments
        .map(_EventImageData.tryParse)
        .whereType<_EventImageData>()
        .toList();
    if (images.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          for (var index = 0; index < images.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 8),
            _UserImageTile(image: images[index]),
          ],
        ],
      ),
    );
  }
}

class _UserImageTile extends StatelessWidget {
  const _UserImageTile({required this.image});

  final _EventImageData image;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: colors.surfaceOverlay,
        child: InkWell(
          onTap: () => _showEventImagePreview(context, image),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: colors.glassBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: _EventImage(
              image: image,
              fit: BoxFit.cover,
              errorColor: colors.textMuted,
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
              child: _EventImage(
                image: image,
                fit: BoxFit.contain,
                errorColor: colors.textMuted,
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
                    child: _EventImage(
                      image: image,
                      fit: BoxFit.contain,
                      preview: true,
                      errorColor: Colors.white70,
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
  const _EventImageData({
    this.thumbnailBytes,
    this.originalBytes,
    this.resourceUri,
  });

  final Uint8List? thumbnailBytes;
  final Uint8List? originalBytes;
  final Uri? resourceUri;

  static _EventImageData? tryParse(EventAttachment attachment) {
    final thumbnailBytes = _decodeImageDataUrl(attachment.thumbnailDataUrl);
    final originalBytes = _decodeImageDataUrl(attachment.dataUrl);
    final resourceUri = _isExpired(attachment.expiresAt)
        ? null
        : _safeImageUri(attachment.resourceUrl);
    if (thumbnailBytes == null &&
        originalBytes == null &&
        resourceUri == null) {
      return null;
    }
    return _EventImageData(
      thumbnailBytes: thumbnailBytes,
      originalBytes: originalBytes,
      resourceUri: resourceUri,
    );
  }
}

class _EventImage extends StatelessWidget {
  const _EventImage({
    required this.image,
    required this.fit,
    required this.errorColor,
    this.preview = false,
  });

  final _EventImageData image;
  final BoxFit fit;
  final Color errorColor;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final bytes = preview
        ? image.originalBytes
        : image.thumbnailBytes ?? image.originalBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _brokenImage(errorColor),
      );
    }
    final uri = image.resourceUri;
    if (preview && uri == null && image.thumbnailBytes != null) {
      return Image.memory(
        image.thumbnailBytes!,
        fit: fit,
        gaplessPlayback: true,
      );
    }
    if (uri == null) return _brokenImage(errorColor);
    return Image.network(
      uri.toString(),
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _brokenImage(errorColor),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              value: progress.expectedTotalBytes == null
                  ? null
                  : progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!,
              color: errorColor,
            ),
          ),
        );
      },
    );
  }

  Widget _brokenImage(Color color) {
    return Center(
      child: Icon(RecodexIcons.brokenImage, color: color, size: 22),
    );
  }
}

const _maxInlineImageBytes = 2 * 1024 * 1024;

bool _isRenderableImageAttachment(EventAttachment attachment) {
  final type = attachment.type.trim().toLowerCase();
  final mime = attachment.mime.trim().toLowerCase();
  final isImage = type == 'image' || mime.startsWith('image/');
  return isImage && attachment.hasImageSource;
}

Uint8List? _decodeImageDataUrl(String value) {
  final dataUrl = value.trim();
  if (!dataUrl.startsWith('data:image/')) return null;
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0 || !dataUrl.substring(0, commaIndex).contains(';base64')) {
    return null;
  }
  try {
    final bytes = base64Decode(dataUrl.substring(commaIndex + 1));
    return bytes.length <= _maxInlineImageBytes ? bytes : null;
  } on FormatException {
    return null;
  }
}

Uri? _safeImageUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.userInfo.isNotEmpty || uri.host.isEmpty) return null;
  if (uri.scheme == 'https') return uri;
  if (uri.scheme == 'http' &&
      (uri.host == '127.0.0.1' ||
          uri.host == 'localhost' ||
          uri.host == '::1')) {
    return uri;
  }
  return null;
}

bool _isExpired(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return false;
  final parsedDate = DateTime.tryParse(raw);
  if (parsedDate != null) return !parsedDate.isAfter(DateTime.now());
  final numeric = num.tryParse(raw);
  if (numeric == null) return true;
  final milliseconds = numeric.abs() < 100000000000
      ? (numeric * 1000).round()
      : numeric.round();
  return milliseconds <= DateTime.now().millisecondsSinceEpoch;
}

class EventTimelineItem extends StatelessWidget {
  const EventTimelineItem({required this.event, this.onUndo, super.key});

  final SessionEvent event;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    if (_isFileChangeEvent(event.kind)) {
      final paths = _fileChangePathList(event.text);
      return ToolCallRow(
        title: '已修改文件',
        status: paths.isEmpty ? '文件变更' : '${paths.length} 个文件',
        icon: RecodexIcons.edit,
      );
    }
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

class AssistantAnswerBlock extends StatefulWidget {
  const AssistantAnswerBlock({
    required this.events,
    required this.completed,
    this.status,
    this.startedAt,
    this.showReasoning = true,
    this.collapseReasoningByDefault = true,
    this.showToolCallDetails = true,
    this.showUsageMetrics = true,
    this.cardRadius = 24,
    this.maxWidth = 960,
    this.gitChangeSummary,
    this.onGitFileTap,
    this.onUndoGitChanges,
    super.key,
  });

  final List<SessionEvent> events;
  final bool completed;

  /// Optional explicit lifecycle state from the bridge. Older callers can
  /// continue to provide only [completed], which maps to the same Codex
  /// completed/processing presentation.
  final TimelineTaskStatus? status;
  final DateTime? startedAt;
  final bool showReasoning;
  final bool collapseReasoningByDefault;
  final bool showToolCallDetails;
  final bool showUsageMetrics;
  final double cardRadius;
  final double maxWidth;
  final GitChangeSummary? gitChangeSummary;
  final ValueChanged<GitFileChange>? onGitFileTap;
  final VoidCallback? onUndoGitChanges;

  @override
  State<AssistantAnswerBlock> createState() => _AssistantAnswerBlockState();
}

class _AssistantAnswerBlockState extends State<AssistantAnswerBlock> {
  late bool _reasoningExpanded;

  @override
  void initState() {
    super.initState();
    // Codex keeps the live reasoning visible while a turn is running, then
    // folds it when the final answer arrives.
    _reasoningExpanded =
        !widget.completed || !widget.collapseReasoningByDefault;
  }

  @override
  void didUpdateWidget(covariant AssistantAnswerBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.completed && widget.completed) {
      _reasoningExpanded = false;
    } else if (oldWidget.completed && !widget.completed) {
      _reasoningExpanded = true;
    } else if (oldWidget.collapseReasoningByDefault !=
            widget.collapseReasoningByDefault &&
        widget.completed) {
      _reasoningExpanded = !widget.collapseReasoningByDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskStatus =
        widget.status ??
        (widget.completed
            ? TimelineTaskStatus.completed
            : TimelineTaskStatus.processing);
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final answerChildren = <Widget>[];
    final reasoningSteps = <_AnswerStep>[];
    final gitSummaries = <GitChangeSummary>[];
    final fileChangePaths = <String>{};
    var fileChangeStepIndex = -1;
    TokenUsage? usage;
    var hasTerminalEvent = false;
    SessionEvent? latestLiveEvent;
    // The bridge's explicit lifecycle is authoritative for the selected
    // turn. Historical `done`/`interrupted` markers can remain in the merged
    // transcript when a task is refreshed during reconnect; they must not
    // make a still-running turn render as completed or interrupted.
    final statusIsActive = taskStatus.isActive;

    void mergeUsage(TokenUsage next) {
      final previous = usage;
      if (previous == null || next.totalTokens >= previous.totalTokens) {
        usage = next;
        return;
      }
      usage = TokenUsage(
        inputTokens: previous.inputTokens + next.inputTokens,
        outputTokens: previous.outputTokens + next.outputTokens,
        totalTokens: previous.totalTokens + next.totalTokens,
      );
    }

    void flushAnswerText() {
      final text = textBuffer.toString().trim();
      if (text.isEmpty) return;
      if (answerChildren.isNotEmpty) {
        answerChildren.add(const SizedBox(height: 18));
      }
      answerChildren.add(
        _AnswerText(
          text: text,
          cardRadius: widget.cardRadius,
          gitChangeSummary: widget.gitChangeSummary,
          onFileTap: widget.onGitFileTap,
        ),
      );
      textBuffer.clear();
    }

    void flushReasoningText() {
      final text = reasoningBuffer.toString().trim();
      if (text.isEmpty) return;
      reasoningSteps.add(
        _AnswerStep(icon: RecodexIcons.reasoning, title: text),
      );
      reasoningBuffer.clear();
    }

    for (final event in widget.events) {
      final eventUsage = event.usage;
      if (eventUsage != null) mergeUsage(eventUsage);
      if (_isDoneEvent(event.kind)) {
        if (!statusIsActive) hasTerminalEvent = true;
        continue;
      }
      if (event.kind == 'token_usage') {
        continue;
      }
      if (event.kind == 'running') {
        flushAnswerText();
        latestLiveEvent = event;
        continue;
      }
      if (event.kind == 'interrupted') {
        if (statusIsActive) continue;
        hasTerminalEvent = true;
        flushAnswerText();
        reasoningSteps.add(
          const _AnswerStep(
            icon: RecodexIcons.pause,
            title: '已中断',
            detail: '用户取消',
          ),
        );
        continue;
      }
      if (event.kind.toLowerCase().contains('reason')) {
        if (!widget.showReasoning) continue;
        reasoningBuffer.write(_cleanEventText(event));
        continue;
      }
      if (_isFileChangeEvent(event.kind)) {
        if (!widget.showToolCallDetails) {
          latestLiveEvent = null;
          continue;
        }
        flushReasoningText();
        fileChangePaths.addAll(_fileChangePathList(event.text));
        final count = fileChangePaths.length;
        final step = _AnswerStep(
          icon: RecodexIcons.edit,
          title: statusIsActive ? '正在修改文件' : '已修改文件',
          detail: count > 0 ? '$count 个文件' : null,
        );
        if (fileChangeStepIndex < 0) {
          fileChangeStepIndex = reasoningSteps.length;
          reasoningSteps.add(step);
        } else {
          reasoningSteps[fileChangeStepIndex] = step;
        }
        latestLiveEvent = event.copyWith(text: fileChangePaths.join('\n'));
        continue;
      }
      if (_isToolEvent(event.kind)) {
        if (!widget.showToolCallDetails) {
          latestLiveEvent = null;
          continue;
        }
        flushReasoningText();
        reasoningSteps.add(
          _AnswerStep.fromToolEvent(
            event,
            includeDetail: widget.showToolCallDetails,
          ),
        );
        latestLiveEvent = event;
        continue;
      }
      final gitSummary = GitChangeSummary.tryParse(event.text);
      if (gitSummary != null) {
        flushAnswerText();
        gitSummaries.add(gitSummary);
        reasoningSteps.add(
          _AnswerStep(
            icon: RecodexIcons.gitCompare,
            title: '已更新文件',
            detail: '${gitSummary.files.length} 个文件',
          ),
        );
        continue;
      }
      final imageCount = event.attachments
          .where(_isRenderableImageAttachment)
          .length;
      if (imageCount > 0) {
        reasoningSteps.add(
          _AnswerStep(icon: RecodexIcons.image, title: '已查看 $imageCount 张图像'),
        );
      }
      final text = _cleanEventText(event);
      if (text.isEmpty) continue;
      flushReasoningText();
      if (textBuffer.isNotEmpty && _shouldSeparateText(event.kind)) {
        textBuffer.writeln();
        textBuffer.writeln();
      }
      textBuffer.write(text);
    }
    flushAnswerText();
    flushReasoningText();
    final mergedGitSummary = _mergeGitSummaries(gitSummaries);
    if (mergedGitSummary != null) {
      if (answerChildren.isNotEmpty) {
        answerChildren.add(const SizedBox(height: 18));
      }
      answerChildren.add(
        _GitChangePanel(
          summary: mergedGitSummary,
          cardRadius: widget.cardRadius,
          onUndo: widget.onUndoGitChanges,
          onFileTap: widget.onGitFileTap,
        ),
      );
    }
    final statusIsTerminal = taskStatus.isTerminal;
    if (!widget.completed && !statusIsTerminal && !hasTerminalEvent) {
      if (answerChildren.isNotEmpty) {
        answerChildren.add(const SizedBox(height: 18));
      }
      answerChildren.add(
        latestLiveEvent == null
            ? const _LiveActivityRow(text: '正在生成回答...')
            : _LiveActivityRow.fromEvent(latestLiveEvent),
      );
    }

    final isDone = widget.completed || statusIsTerminal || hasTerminalEvent;
    if (answerChildren.isEmpty && (isDone || reasoningSteps.isEmpty)) {
      final fallbackText = switch (taskStatus) {
        TimelineTaskStatus.failed => '任务执行失败。',
        TimelineTaskStatus.interrupted => '任务已中断。',
        _ => '完成。',
      };
      answerChildren.add(
        isDone
            ? _AnswerText(
                text: fallbackText,
                cardRadius: widget.cardRadius,
                gitChangeSummary: widget.gitChangeSummary,
                onFileTap: widget.onGitFileTap,
              )
            : const _LiveActivityRow(text: '正在思考...'),
      );
    }
    if (!isDone && reasoningSteps.isEmpty) {
      reasoningSteps.add(
        const _AnswerStep(icon: RecodexIcons.reasoning, title: '正在思考'),
      );
    }
    final elapsed = _elapsedLabel(
      widget.events,
      startedAt: widget.startedAt,
      active: taskStatus.isActive,
    );
    final hasReasoning = reasoningSteps.isNotEmpty;
    final reduceAnimations = MediaQuery.of(context).disableAnimations;
    return Align(
      // Keep the answer column centered in the available transcript area.
      // The width remains fluid below the configured maximum, so narrow
      // windows do not overflow while wide windows retain a readable column.
      alignment: Alignment.center,
      child: ConstrainedBox(
        // Codex keeps assistant output in a readable desktop column instead
        // of stretching a response card across the entire conversation pane.
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AnswerStatusHeader(
                  done: isDone,
                  status: taskStatus,
                  showCompletedLabel: widget.status != null,
                  elapsed: widget.showUsageMetrics ? elapsed : null,
                  usage: widget.showUsageMetrics ? usage : null,
                  expanded: _reasoningExpanded,
                  hasReasoning: hasReasoning,
                  onToggle: hasReasoning
                      ? () => setState(
                          () => _reasoningExpanded = !_reasoningExpanded,
                        )
                      : null,
                ),
                if (hasReasoning && _reasoningExpanded) ...[
                  const SizedBox(height: 16),
                  AnimatedSize(
                    duration: reduceAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _ReasoningContent(steps: reasoningSteps),
                  ),
                ],
                if (answerChildren.isNotEmpty) ...[
                  if (hasReasoning && _reasoningExpanded)
                    const SizedBox(height: 22),
                  ...answerChildren,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasoningContent extends StatelessWidget {
  const _ReasoningContent({required this.steps});

  final List<_AnswerStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < steps.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 12),
          steps[index].icon == RecodexIcons.reasoning
              ? _ReasoningTextRow(text: steps[index].title)
              : _AnswerStepRow(step: steps[index]),
        ],
      ],
    );
  }
}

class _ReasoningTextRow extends StatelessWidget {
  const _ReasoningTextRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Text(
      text,
      style: TextStyle(
        color: colors.text.withValues(alpha: 0.92),
        fontSize: _scaledFontSize(15, fontScale),
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _AnswerStep {
  const _AnswerStep({required this.icon, required this.title, this.detail});

  factory _AnswerStep.fromToolEvent(
    SessionEvent event, {
    bool includeDetail = true,
  }) {
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
    final detail = includeDetail
        ? command == null
              ? _shortenText(event.text, fallback: '')
              : _formatCommand(command)
        : null;
    return _AnswerStep(
      icon: RecodexIcons.edit,
      title: title,
      detail: detail?.isEmpty == true ? null : detail,
    );
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
              fontWeight: FontWeight.w500,
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
    if (_isFileChangeEvent(event.kind)) {
      final paths = _fileChangePathList(event.text);
      return _LiveActivityRow(
        text: paths.length == 1 ? '正在修改 ${_baseName(paths.first)}' : '正在修改文件',
        detail: paths.length > 1 ? '${paths.length} 个文件' : '正在思考',
      );
    }
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
                fontWeight: FontWeight.w500,
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
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerStatusHeader extends StatelessWidget {
  const _AnswerStatusHeader({
    required this.done,
    required this.status,
    required this.showCompletedLabel,
    required this.elapsed,
    required this.usage,
    required this.expanded,
    required this.hasReasoning,
    this.onToggle,
  });

  final bool done;
  final TimelineTaskStatus status;
  final bool showCompletedLabel;
  final String? elapsed;
  final TokenUsage? usage;
  final bool expanded;
  final bool hasReasoning;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final statusLabel = status == TimelineTaskStatus.unknown && done
        ? TimelineTaskStatus.completed.label
        : status.label;
    final statusColor = switch (status) {
      TimelineTaskStatus.waitingApproval => colors.warning,
      TimelineTaskStatus.failed => colors.error,
      _ => colors.textMuted,
    };
    final compactCompleted =
        status == TimelineTaskStatus.completed && showCompletedLabel;
    final legacyCompactMetrics =
        status == TimelineTaskStatus.completed &&
        !showCompletedLabel &&
        elapsed != null;
    final metrics = <String>[
      if (!compactCompleted && elapsed != null) '用时 $elapsed',
      if (usage != null) 'Token ${_formatTokenCount(usage!.totalTokens)}',
    ];
    // The official client uses a compact success label (`已处理 7 分钟 17
    // 秒`). Keep the old metrics-only form for callers that do not provide an
    // explicit lifecycle snapshot, while naming every active/exception state.
    final showStatusLabel = !legacyCompactMetrics && !compactCompleted;
    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compactCompleted)
          Text(
            elapsed == null ? '已处理' : '已处理 $elapsed',
            style: TextStyle(
              color: statusColor,
              fontSize: _scaledFontSize(15, fontScale),
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
          )
        else if (showStatusLabel)
          Text(
            statusLabel.isEmpty ? (done ? '已完成' : '正在思考') : statusLabel,
            style: TextStyle(
              color: statusColor,
              fontSize: _scaledFontSize(15, fontScale),
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
          ),
        for (final metric in metrics) ...[
          if (showStatusLabel || compactCompleted) ...[
            const SizedBox(width: 8),
            Text(
              '·',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(15, fontScale),
                height: 1.2,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            metric,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: _scaledFontSize(15, fontScale),
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        if (hasReasoning) ...[
          const SizedBox(width: 8),
          Icon(
            expanded ? RecodexIcons.chevronDown : RecodexIcons.chevronRight,
            size: 16,
            color: colors.textMuted,
          ),
        ],
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.16)),
      ],
    );
    if (!hasReasoning || onToggle == null) return content;
    return Semantics(
      button: true,
      label: expanded ? '收起执行过程' : '展开执行过程',
      child: Tooltip(
        message: expanded ? '收起执行过程' : '展开执行过程',
        child: InkWell(
          key: const ValueKey('answer-reasoning-toggle'),
          borderRadius: BorderRadius.circular(6),
          // The reasoning header is intentionally text-only. Keep the
          // pointer cursor and click affordance without painting a grey
          // hover capsule behind the row.
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _AnswerText extends StatelessWidget {
  const _AnswerText({
    required this.text,
    this.cardRadius = 24,
    this.gitChangeSummary,
    this.onFileTap,
  });

  final String text;
  final double cardRadius;
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
          cardRadius: cardRadius,
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
    final leadingWhitespace = RegExp(r'^\s*').firstMatch(text)?.group(0);
    final depth = math.min(3, (leadingWhitespace?.length ?? 0) ~/ 2);
    final trimmed = text.trimLeft();
    final bullet = RegExp(r'^[-*+•◦○]\s+').firstMatch(trimmed);
    final isBullet = bullet != null;
    final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(trimmed);
    final isLabelHeading =
        !isBullet &&
        heading == null &&
        trimmed.length <= 36 &&
        RegExp(r'[：:]$').hasMatch(trimmed);
    final isHeading = !isBullet && (heading != null || isLabelHeading);
    final content = isBullet
        ? trimmed.substring(bullet.end).trimLeft()
        : heading?.group(1) ?? text;
    final richText = Text.rich(
      TextSpan(children: _inlineSpans(context, content)),
      style: TextStyle(
        color: colors.text,
        fontSize: _scaledFontSize(isHeading ? 16.5 : 15.5, fontScale),
        height: 1.55,
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
      padding: EdgeInsets.only(left: depth * 20.0, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(
              RecodexIcons.circle,
              size: depth == 0 ? 6 : 5,
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
  const _ModifiedFilesBlock({
    required this.files,
    this.cardRadius = 22,
    this.onFileTap,
  });

  final List<_ModifiedFileReference> files;
  final double cardRadius;
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
          borderRadius: BorderRadius.circular(
            _conversationCardRadius(cardRadius),
          ),
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
                        fontWeight: FontWeight.w500,
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
                fontWeight: FontWeight.w500,
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
    this.cardRadius = 20,
    this.onTap,
    super.key,
  });

  final String title;
  final String status;
  final IconData icon;
  final double cardRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(
          _conversationCardRadius(cardRadius),
        ),
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
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              status,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w400,
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
          borderRadius: BorderRadius.circular(
            _conversationCardRadius(cardRadius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(
              _conversationCardRadius(cardRadius),
            ),
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
    this.cardRadius = 22,
    this.onUndo,
    this.onFileTap,
    super.key,
  });

  final GitChangeSummary summary;
  final double cardRadius;
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
          cardRadius: cardRadius,
          onUndo: onUndo,
          onFileTap: onFileTap,
        ),
      ),
    );
  }
}

class _GitChangePanel extends StatelessWidget {
  const _GitChangePanel({
    required this.summary,
    this.cardRadius = 22,
    this.onUndo,
    this.onFileTap,
  });

  final GitChangeSummary summary;
  final double cardRadius;
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
        borderRadius: BorderRadius.circular(
          _conversationCardRadius(cardRadius),
        ),
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
                            fontWeight: FontWeight.w600,
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
                  fontWeight: FontWeight.w500,
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
        fontWeight: FontWeight.w600,
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
    this.focusNode,
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
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ComposerGlassPanel(
          // Codex keeps a compact desktop rhythm: a short input row with a
          // single control row below it, rather than a tall mobile field.
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          radius: 28,
          child: Column(
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled && !running,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask anything... @files, \$skills, /commands',
                  hintStyle: TextStyle(
                    color: colors.textMuted.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
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
                      // Keep the primary action in the same visual rhythm as
                      // the compact selector pills beside it. The hit target
                      // remains easy to reach while the circular button no
                      // longer dominates the composer row.
                      dimension: 36,
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
                          size: running ? 18 : 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        fontWeight: FontWeight.w500,
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
        minimumSize: const Size(38, 38),
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
      showBorder: false,
      tooltip: '选择$label',
      onChanged: onChanged,
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
      showBorder: false,
      tooltip: '选择权限模式',
      onChanged: onChanged,
    );
  }
}

String _reasoningLabel(String value) {
  return switch (value) {
    'minimal' => '最低',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    'max' => '最高',
    'ultra' => '极致',
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
              fontSize: 14,
              height: 1.12,
              fontWeight: FontWeight.w500,
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

bool _isFileChangeEvent(String kind) {
  final normalized = kind.trim().toLowerCase().replaceAll('-', '_');
  return normalized == 'filechange' ||
      normalized == 'file_change' ||
      normalized == 'filechanged' ||
      normalized == 'file_changed';
}

List<String> _fileChangePathList(String raw) {
  final paths = <String>{};
  for (final value in raw.split(RegExp(r'[\n,;]'))) {
    var path = value.trim();
    path = path.replaceFirst(RegExp(r'''^["']'''), '');
    path = path.replaceFirst(RegExp(r'''["']$'''), '');
    final normalized = path.toLowerCase();
    if (path.isEmpty ||
        normalized == 'filechange' ||
        normalized == 'file_change' ||
        normalized == 'updated' ||
        normalized == 'modified' ||
        normalized == 'changed') {
      continue;
    }
    paths.add(path);
  }
  return paths.toList(growable: false);
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

String? _elapsedLabel(
  List<SessionEvent> events, {
  DateTime? startedAt,
  bool active = false,
}) {
  int? measuredDurationMs;
  for (final event in events) {
    final durationMs = event.durationMs;
    if (durationMs != null && durationMs >= 0) {
      measuredDurationMs = durationMs;
    }
  }
  if (active && startedAt != null) {
    final elapsed = DateTime.now().difference(startedAt);
    if (!elapsed.isNegative) return _formatElapsed(elapsed);
  }

  if (measuredDurationMs != null) {
    return _formatElapsed(Duration(milliseconds: measuredDurationMs));
  }

  final times = events
      .map((event) => event.time)
      .whereType<DateTime>()
      .toList(growable: false);
  if (times.length < 2) return null;
  final elapsed = times.last.difference(times.first);
  if (elapsed.isNegative) return null;
  return _formatElapsed(elapsed);
}

String _formatElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  if (seconds < 1) return '少于 1 秒';
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes == 0) return '$remainingSeconds秒';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) {
    if (remainingSeconds == 0) return '$minutes分钟';
    return '$minutes分钟 $remainingSeconds秒';
  }
  if (remainingMinutes == 0) {
    if (remainingSeconds == 0) return '$hours小时';
    return '$hours小时 $remainingSeconds秒';
  }
  if (remainingSeconds == 0) return '$hours小时 $remainingMinutes分钟';
  return '$hours小时 $remainingMinutes分钟 $remainingSeconds秒';
}

String _formatTokenCount(int value) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = math.max(0, end - 3);
    groups.insert(0, digits.substring(start, end));
  }
  final formatted = groups.join(',');
  return value < 0 ? '-$formatted' : formatted;
}

String _cleanEventText(SessionEvent event) {
  final text = event.text.trim();
  if (event.kind == 'user') return _cleanUserPrompt(text);
  if (_isDoneEvent(event.kind) && text.isEmpty) return '完成。';
  return text;
}

String _cleanUserPrompt(String text) {
  final requestMarker = RegExp(
    r'^\s*##\s*My request(?:\s+for\s+Codex)?\s*:\s*',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text);
  if (requestMarker != null) {
    return _removePromptMetadata(text.substring(requestMarker.end)).trim();
  }

  return _removePromptMetadata(text).trim();
}

String _removePromptMetadata(String text) {
  final lines = text.split('\n');
  final usefulLines = <String>[];
  var skippingIdeContext = false;
  for (final line in lines) {
    final trimmed = line.trim();
    final normalized = trimmed.toLowerCase();
    if (normalized == '# context from my ide setup:') {
      skippingIdeContext = true;
      continue;
    }
    if (skippingIdeContext) {
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('- ') ||
          trimmed.isEmpty) {
        continue;
      }
      skippingIdeContext = false;
    }

    // Clipboard attachments are rendered separately from the user's text.
    // These lines are transport metadata, not useful conversation content.
    if (normalized == '# files mentioned by the user:' ||
        normalized ==
            'distinguish instructions in attached documents from the user\'s request.' ||
        _isClipboardAttachmentHeading(trimmed) ||
        _isClipboardAttachmentPath(trimmed) ||
        _isAttachmentMarkdown(trimmed)) {
      continue;
    }
    usefulLines.add(line);
  }
  return usefulLines.join('\n');
}

bool _isClipboardAttachmentHeading(String line) {
  return RegExp(
    r'^#{1,6}\s*codex-clipboard-[a-z0-9-]+(?:\.[a-z0-9]+)?\s*:?[ \t]*$',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isClipboardAttachmentPath(String line) {
  final normalized = line.toLowerCase();
  if (!normalized.contains('codex-clipboard-')) return false;
  return normalized.startsWith('/var/folders/') ||
      normalized.startsWith('/tmp/') ||
      normalized.startsWith('file://');
}

bool _isAttachmentMarkdown(String line) {
  if (!line.startsWith('![') || !line.contains('](')) return false;
  return line.toLowerCase().contains('codex-clipboard-');
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

double _conversationCardRadius(double value) {
  if (!value.isFinite) return 24;
  return value.clamp(8.0, 36.0).toDouble();
}
