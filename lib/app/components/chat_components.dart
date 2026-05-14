import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/bridge_models.dart';
import '../pages/settings/theme_controller.dart';
import '../theme/recodex_theme.dart';

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
            child: SelectableText(
              text.isEmpty ? '暂无输出' : text,
              style: TextStyle(
                fontSize: _scaledFontSize(16, fontScale),
                height: 1.62,
                color: isError ? colors.error : colors.text,
                fontWeight: isUser ? FontWeight.w500 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
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
        icon: Icons.terminal,
      );
    }
    if (_isDoneEvent(event.kind)) {
      return ToolCallRow(
        title: '已处理',
        status: event.text.trim().isEmpty
            ? '完成'
            : _shortenText(event.text, fallback: '完成'),
        icon: Icons.check_circle_outline,
      );
    }
    if (event.kind == 'interrupted') {
      return const ToolCallRow(
        title: '已中断',
        status: '用户取消',
        icon: Icons.pause_circle_outline,
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
    final colors = context.recodexColors;
    final textBuffer = StringBuffer();
    final children = <Widget>[];
    var hasTerminalEvent = false;

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
        children.add(const _LiveActivityRow(text: '正在思考...'));
        continue;
      }
      if (event.kind == 'interrupted') {
        hasTerminalEvent = true;
        flushText();
        children.add(
          const _InlineStatusRow(
            icon: Icons.pause_circle_outline,
            title: '已中断',
            detail: '用户取消',
          ),
        );
        continue;
      }
      if (_isToolEvent(event.kind)) {
        flushText();
        final command = _extractCommand(event.text);
        children.add(
          _LiveActivityRow(
            text: command == null
                ? '正在运行工具'
                : '正在运行 ${_formatCommand(command)}',
            detail: '正在思考',
          ),
        );
        continue;
      }
      final gitSummary = GitChangeSummary.tryParse(event.text);
      if (gitSummary != null) {
        flushText();
        children.add(
          _GitChangePanel(
            summary: gitSummary,
            onUndo: onUndoGitChanges,
            onFileTap: onGitFileTap,
          ),
        );
        continue;
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
    final usage = _latestUsage(events);
    final activeColor = Theme.of(context).colorScheme.primary;

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDone
                ? colors.assistantBubble
                : activeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDone
                  ? colors.glassBorder
                  : activeColor.withValues(alpha: 0.48),
              width: isDone ? 1 : 1.4,
            ),
            boxShadow: isDone
                ? null
                : [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.22),
                      offset: const Offset(0, 16),
                      blurRadius: 34,
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AnswerStatusHeader(
                  done: isDone,
                  elapsed: elapsed,
                  usage: usage,
                ),
                const SizedBox(height: 18),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveActivityRow extends StatelessWidget {
  const _LiveActivityRow({required this.text, this.detail});

  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.terminal,
                  size: 17,
                  color: colors.textMuted.withValues(alpha: 0.86),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: _scaledFontSize(15, fontScale),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if ((detail ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: _scaledFontSize(15, fontScale),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnswerStatusHeader extends StatelessWidget {
  const _AnswerStatusHeader({
    required this.done,
    required this.elapsed,
    required this.usage,
  });

  final bool done;
  final String? elapsed;
  final TokenUsage? usage;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final activeColor = Theme.of(context).colorScheme.primary;
    final label = done
        ? elapsed == null
              ? '已处理'
              : '已处理 $elapsed'
        : elapsed == null
        ? '正在思考...'
        : '正在思考... $elapsed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (done)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: _scaledFontSize(14, fontScale),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: colors.textMuted, size: 19),
              if (usage != null) ...[
                const SizedBox(width: 10),
                _TokenUsagePill(usage: usage!),
              ],
            ],
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: activeColor.withValues(alpha: 0.28)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: activeColor,
                      fontSize: _scaledFontSize(14, fontScale),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Divider(
          height: 1,
          color: (done ? colors.textMuted : activeColor).withValues(
            alpha: 0.16,
          ),
        ),
      ],
    );
  }
}

class _TokenUsagePill extends StatelessWidget {
  const _TokenUsagePill({required this.usage});

  final TokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '${_formatCompactNumber(usage.totalTokens)} tokens',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
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
        fontWeight: isHeading ? FontWeight.w600 : FontWeight.w300,
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
            child: Icon(Icons.circle, size: 5.5, color: colors.textMuted),
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
              ? const Color(0xff17181c).withValues(alpha: 0.86)
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
                  Icon(Icons.expand_more, size: 22, color: colors.textMuted),
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
          Icon(Icons.expand_more, size: 22, color: colors.textMuted),
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

class _InlineStatusRow extends StatelessWidget {
  const _InlineStatusRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.userBubble.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.textMuted),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: _scaledFontSize(14, fontScale),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    required this.title,
    required this.status,
    this.icon = Icons.check_circle_outline,
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
        ? const Color(0xff17181c).withValues(alpha: 0.86)
        : colors.assistantBubble.withValues(alpha: 0.78);
    final rowDivider = colors.textMuted.withValues(alpha: isDark ? 0.14 : 0.12);
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
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${summary.files.length} 个文件',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: _scaledFontSize(16.5, fontScale),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DeltaText(
                        added: summary.added,
                        removed: summary.removed,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _GitActionButton(
                  icon: Icons.undo,
                  tooltip: '撤销',
                  onPressed: onUndo,
                ),
                _GitActionButton(
                  icon: Icons.north_east,
                  tooltip: '审核',
                  onPressed: summary.files.isEmpty ? null : () {},
                ),
                _GitActionButton(
                  icon: Icons.open_in_full,
                  tooltip: '展开',
                  onPressed: summary.files.isEmpty ? null : () {},
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
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    final fileName = _baseName(file.path);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: fileName.isEmpty ? file.path : fileName),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: '+${file.added}',
                    style: TextStyle(color: colors.success),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '-${file.removed}',
                    style: TextStyle(color: colors.error),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: _scaledFontSize(15.5, fontScale),
                fontWeight: FontWeight.w900,
                height: 1.12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.expand_more, size: 22, color: colors.textMuted),
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
    required this.onSend,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onVoicePressed,
    this.listening = false,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final ComposerContext context;
  final VoidCallback onSend;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
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
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          radius: 32,
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: colors.glassBorder.withValues(
                      alpha: isDark ? 0.46 : 0.96,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.glassHighlight.withValues(
                        alpha: isDark ? 0.04 : 0.62,
                      ),
                      offset: const Offset(-3, -3),
                      blurRadius: 10,
                    ),
                    BoxShadow(
                      color: colors.headerShadow.withValues(
                        alpha: isDark ? 0.28 : 0.08,
                      ),
                      offset: const Offset(0, 5),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: TextField(
                  controller: controller,
                  enabled: enabled,
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
                    contentPadding: const EdgeInsets.fromLTRB(14, 9, 14, 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ComposerIconButton(
                    icon: Icons.add,
                    onPressed: enabled ? () {} : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ComposerMenuButton(
                            icon: Icons.bolt,
                            label: this.context.model,
                            values: this.context.models,
                            onChanged: onModelChanged,
                          ),
                          const SizedBox(width: 6),
                          _ComposerMenuButton(
                            icon: Icons.blur_circular,
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
                    icon: listening ? Icons.mic : Icons.mic_none,
                    active: listening,
                    onPressed: enabled ? onVoicePressed : null,
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 48,
                    child: FilledButton(
                      onPressed: enabled ? onSend : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.72),
                        foregroundColor: const Color(0xff7d848c),
                        disabledBackgroundColor: Colors.white.withValues(
                          alpha: 0.56,
                        ),
                        disabledForegroundColor: const Color(0xffb6bcc4),
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        elevation: 0,
                      ),
                      child: const Icon(Icons.arrow_upward, size: 26),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ContextMenuPill(
                icon: Icons.laptop_mac_outlined,
                label: this.context.transport,
                items: [
                  _ContextMenuItem(
                    icon: Icons.laptop_mac_outlined,
                    title: this.context.transport,
                    subtitle: '本机 Bridge 上下文',
                  ),
                  _ContextMenuItem(
                    icon: Icons.account_tree_outlined,
                    title: this.context.branch.isEmpty
                        ? '未读取分支'
                        : this.context.branch,
                    subtitle: '当前 Git 分支',
                  ),
                  _ContextMenuItem(
                    icon: Icons.shield_outlined,
                    title: this.context.requireConfirmGitWrite
                        ? 'Git 写操作需确认'
                        : '信任当前工作区',
                    subtitle: '权限策略',
                  ),
                ],
              ),
              const SizedBox(width: 10),
              _ContextPill(
                icon: Icons.shield_outlined,
                label: this.context.requireConfirmGitWrite
                    ? 'Confirm'
                    : 'Trusted',
                warning: this.context.requireConfirmGitWrite,
                trailing: Icons.keyboard_arrow_down,
              ),
              const SizedBox(width: 18),
              _ContextPill(
                icon: Icons.account_tree_outlined,
                label: this.context.branch.isEmpty
                    ? 'branch'
                    : this.context.branch,
              ),
              const SizedBox(width: 10),
              _ContextPill(
                icon: Icons.cloud_done_outlined,
                label: this.context.approvalPolicy,
              ),
            ],
          ),
        ),
      ],
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
    final baseAlpha = isDark ? 0.70 : 0.76;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(alpha: isDark ? 0.58 : 0.24),
            offset: const Offset(0, 24),
            blurRadius: 42,
          ),
          BoxShadow(
            color: colors.icon.withValues(alpha: isDark ? 0.16 : 0.10),
            offset: const Offset(0, 9),
            blurRadius: 28,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 72, sigmaY: 72),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              color: colors.glassColor.withValues(alpha: baseAlpha),
              border: Border.all(
                color: colors.glassBorder.withValues(alpha: isDark ? 0.72 : 1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.glassHighlight.withValues(
                    alpha: isDark ? 0.10 : 0.74,
                  ),
                  offset: const Offset(-7, -7),
                  blurRadius: 22,
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  right: 14,
                  top: 1,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.glassHighlight.withValues(
                        alpha: isDark ? 0.18 : 0.92,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
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
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = colors.textMuted;
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (context) => values
          .map(
            (value) => PopupMenuItem<String>(
              value: value,
              child: Text(labelForValue?.call(value) ?? value),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? colors.textMuted : foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({
    required this.icon,
    required this.label,
    this.trailing,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = warning ? colors.warning : colors.textMuted;
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
    return PopupMenuButton<int>(
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
        trailing: Icons.keyboard_arrow_down,
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
    r'`([^`]+)`|((?:/|[A-Za-z]:\\)[^\s，。；、]+(?::\d+)?)',
  ).allMatches(text).toList();
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
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
            match.group(1) ?? match.group(2) ?? '',
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
  if (seconds < 1) return '<1s';
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes == 0) return '${remainingSeconds}s';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) return '${minutes}m ${remainingSeconds}s';
  return '${hours}h ${remainingMinutes}m';
}

TokenUsage? _latestUsage(List<SessionEvent> events) {
  for (final event in events.reversed) {
    if (event.usage != null) return event.usage;
  }
  return null;
}

String _formatCompactNumber(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
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
