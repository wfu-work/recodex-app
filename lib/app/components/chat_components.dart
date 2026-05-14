import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/theme_controller.dart';
import '../models/bridge_models.dart';
import '../theme/recodex_theme.dart';
import 'liquid_glass.dart';

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
                fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
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
    super.key,
  });

  final List<SessionEvent> events;
  final bool completed;

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
      children.add(_AnswerText(text: text));
      textBuffer.clear();
    }

    for (final event in events) {
      if (_isDoneEvent(event.kind)) {
        hasTerminalEvent = true;
        continue;
      }
      if (event.kind == 'running') {
        flushText();
        children.add(
          _LiveActivityRow(text: event.text.isEmpty ? '正在执行任务...' : event.text),
        );
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
            text: command ?? _shortenText(event.text, fallback: '正在调用工具'),
            detail: command ?? _shortenText(event.text, fallback: '工具调用'),
          ),
        );
        continue;
      }
      final gitSummary = GitChangeSummary.tryParse(event.text);
      if (gitSummary != null) {
        flushText();
        children.add(_GitChangePanel(summary: gitSummary));
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

    if (children.isEmpty) {
      children.add(
        _AnswerText(text: completed || hasTerminalEvent ? '完成。' : '暂无输出'),
      );
    }
    final isDone = completed || hasTerminalEvent;
    final elapsed = _elapsedLabel(events);

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.assistantBubble,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.glassBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AnswerStatusHeader(done: isDone, elapsed: elapsed),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                detail ?? text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: _scaledFontSize(14, fontScale),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              done
                  ? elapsed == null
                        ? '已处理'
                        : '已处理 $elapsed'
                  : elapsed == null
                  ? '处理中'
                  : '处理中 $elapsed',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              done ? Icons.chevron_right : Icons.more_horiz,
              color: colors.textMuted,
              size: 19,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.16)),
      ],
    );
  }
}

class _AnswerText extends StatelessWidget {
  const _AnswerText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    var inModifiedFiles = false;

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 12));
        continue;
      }

      if (_isModifiedFilesHeader(line)) {
        inModifiedFiles = true;
        widgets.add(_AnswerLine(text: line));
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      final file = inModifiedFiles ? _extractFileReference(line) : null;
      if (file != null) {
        widgets.add(_ModifiedFileLine(file: file));
        continue;
      }

      widgets.add(_AnswerLine(text: line));
    }

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
    final content = isBullet ? trimmed.substring(2).trimLeft() : text;
    final richText = Text.rich(
      TextSpan(children: _inlineSpans(content)),
      style: TextStyle(
        color: colors.text,
        fontSize: _scaledFontSize(16, fontScale),
        height: 1.5,
        fontWeight: FontWeight.w700,
      ),
    );

    if (!isBullet) return richText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Icon(Icons.circle, size: 6, color: colors.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(child: richText),
        ],
      ),
    );
  }
}

class _ModifiedFileLine extends StatelessWidget {
  const _ModifiedFileLine({required this.file});

  final String file;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 18, color: colors.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _baseName(file),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.icon,
                fontSize: _scaledFontSize(16, fontScale),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
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
                fontWeight: FontWeight.w900,
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
                  fontWeight: FontWeight.w800,
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
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              status,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w800,
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
  const GitChangeCard({required this.summary, this.onUndo, super.key});

  final GitChangeSummary summary;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        alignment: Alignment.centerLeft,
        child: _GitChangePanel(summary: summary, onUndo: onUndo),
      ),
    );
  }
}

class _GitChangePanel extends StatelessWidget {
  const _GitChangePanel({required this.summary, this.onUndo});

  final GitChangeSummary summary;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.userBubble.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
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
                            fontSize: _scaledFontSize(18, fontScale),
                            fontWeight: FontWeight.w900,
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
                  onPressed: null,
                ),
                _GitActionButton(
                  icon: Icons.open_in_full,
                  tooltip: '展开',
                  onPressed: null,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.textMuted.withValues(alpha: 0.16)),
          ...summary.files.map((file) => _GitFileRow(file: file)),
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
  const _GitFileRow({required this.file});

  final GitFileChange file;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final fontScale = Get.find<ThemeController>().fontScale.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 18, color: colors.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _baseName(file.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: _scaledFontSize(14, fontScale),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _DeltaText(added: file.added, removed: file.removed),
        ],
      ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiquidGlass(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          radius: 30,
          opacity: 0.78,
          child: Column(
            children: [
              TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(
                  color: Color(0xff303132),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ask anything... @files, \$skills, /commands',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.fromLTRB(10, 2, 10, 8),
                ),
              ),
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
              const SizedBox(width: 48),
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
    'low' => 'Low',
    'medium' => 'Medium',
    'high' => 'High',
    'xhigh' => 'XHigh',
    _ => value,
  };
}

double _scaledFontSize(double baseSize, double fontScale) {
  return baseSize * fontScale;
}

List<InlineSpan> _inlineSpans(String text) {
  final spans = <InlineSpan>[];
  final matches = RegExp(r'`([^`]+)`').allMatches(text).toList();
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xff202124).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            match.group(1) ?? '',
            style: const TextStyle(
              color: Color(0xff303132),
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.w800,
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

String? _extractFileReference(String line) {
  final trimmed = line.trim();
  final content = (trimmed.startsWith('- ') || trimmed.startsWith('• '))
      ? trimmed.substring(2).trim()
      : trimmed;
  final markdown = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)').firstMatch(content);
  if (markdown != null) {
    return markdown.group(1) ?? markdown.group(2);
  }
  final path = RegExp(r'([^\s`]+\.dart)\b').firstMatch(content);
  return path?.group(1);
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

bool _isToolEvent(String kind) {
  final normalized = kind.toLowerCase();
  return normalized == 'tool' ||
      normalized.contains('exec') ||
      normalized.contains('tool') ||
      normalized.contains('command');
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

String _shortenText(String text, {required String fallback}) {
  final oneLine = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (oneLine.isEmpty) return fallback;
  return oneLine.length <= 36 ? oneLine : '${oneLine.substring(0, 36)}...';
}
