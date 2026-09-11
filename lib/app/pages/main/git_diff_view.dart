import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_notice.dart';
import '../../models/bridge_models.dart';
import '../../services/diff_lines.dart';
import '../../theme/recodex_theme.dart';
import 'bridge_controller.dart';

class GitDiffPageArgs {
  const GitDiffPageArgs({required this.snapshot, required this.selectedPath,
    this.followWorkspace = true});

  final GitSnapshot? snapshot;
  final String selectedPath;
  final bool followWorkspace;
}

class GitDiffPage extends StatelessWidget {
  const GitDiffPage({super.key, this.args});

  final GitDiffPageArgs? args;

  @override
  Widget build(BuildContext context) {
    final pageArgs =
        args ??
        (Get.arguments is GitDiffPageArgs
            ? Get.arguments as GitDiffPageArgs
            : const GitDiffPageArgs(snapshot: null, selectedPath: ''));
    final controller = Get.isRegistered<BridgeController>()
        ? Get.find<BridgeController>()
        : null;
    final body = controller == null || !pageArgs.followWorkspace
        ? _GitDiffBody(
            snapshot: pageArgs.snapshot,
            selectedPath: pageArgs.selectedPath,
          )
        : Obx(() {
            final live = controller.gitSnapshot.value;
            final livePatch = live?.patchForFile(pageArgs.selectedPath) ?? '';
            final snapshot = livePatch.trim().isNotEmpty
                ? live
                : pageArgs.snapshot ?? live;
            return _GitDiffBody(
              snapshot: snapshot,
              selectedPath: pageArgs.selectedPath,
            );
          });
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: '文件变更'),
        body: SafeArea(top: false, child: body),
      ),
    );
  }
}

class _GitDiffBody extends StatelessWidget {
  const _GitDiffBody({required this.snapshot, required this.selectedPath});

  final GitSnapshot? snapshot;
  final String selectedPath;

  @override
  Widget build(BuildContext context) {
    final path = snapshot?.resolveFilePath(selectedPath) ?? selectedPath;
    final diff = snapshot?.patchForFile(selectedPath) ?? '';
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 600 ? 12.0 : 24.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiffFileHeader(
                path: path,
                branch: snapshot?.branch ?? '',
                stat: _fileStat(snapshot, path),
              ),
              const SizedBox(height: 16),
              Expanded(child: _DiffCodePanel(diff: diff)),
            ],
          ),
        );
      },
    );
  }
}

class _DiffFileHeader extends StatelessWidget {
  const _DiffFileHeader({required this.path, required this.branch, this.stat});

  final String path;
  final String branch;
  final _DiffStat? stat;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(RecodexIcons.fileText, color: colors.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _baseName(path).isEmpty ? '文件变更' : _baseName(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (stat != null) ...[
              const SizedBox(width: 16),
              Semantics(
                label: '新增 ${stat!.added} 行，删除 ${stat!.removed} 行',
                child: ExcludeSemantics(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '+${stat!.added}',
                          style: TextStyle(color: colors.success),
                        ),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: '−${stat!.removed}',
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Tooltip(
          message: path,
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        if (branch.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(RecodexIcons.gitCompare, size: 13, color: colors.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  branch.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DiffCodePanel extends StatefulWidget {
  const _DiffCodePanel({required this.diff});

  final String diff;

  @override
  State<_DiffCodePanel> createState() => _DiffCodePanelState();
}

class _DiffCodePanelState extends State<_DiffCodePanel> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  late List<DiffLine> _lines;
  bool _wrapLines = false;
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void initState() {
    super.initState();
    _lines = DiffLine.parse(widget.diff);
  }

  @override
  void didUpdateWidget(covariant _DiffCodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diff != widget.diff) {
      _lines = DiffLine.parse(widget.diff);
      _copied = false;
      _copyTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _copyPatch() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.diff));
      if (!mounted) return;
      _copyTimer?.cancel();
      setState(() => _copied = true);
      _copyTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (_) {
      if (!mounted) return;
      RecodexNotice.show(
        context,
        '复制失败，请重试',
        tone: RecodexNoticeTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final codeStyle = TextStyle(
      color: colors.text,
      fontSize: 13,
      height: 1.7,
      fontWeight: FontWeight.w400,
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['SF Mono', 'Consolas', 'monospace'],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final maxLine = _lines.fold(
                0,
                (number, line) => math.max(
                  number,
                  math.max(line.oldNumber ?? 0, line.newNumber ?? 0),
                ),
              );
              final gutter = math.max(
                constraints.maxWidth < 600 ? 36.0 : 44.0,
                scaler.scale(8) * maxLine.toString().length + 16,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildToolbar(context, gutter),
                  Expanded(
                    child: widget.diff.trim().isEmpty
                        ? const _DiffEmptyState()
                        : _buildCode(
                            context,
                            constraints.maxWidth,
                            gutter,
                            codeStyle,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, double gutter) {
    final colors = context.recodexColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.headerColor,
        border: Border(bottom: BorderSide(color: colors.glassBorder)),
      ),
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        children: [
          for (final label in ['旧行', '新行'])
            SizedBox(
              width: gutter,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '统一差异',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: _wrapLines ? '关闭自动换行' : '自动换行',
            isSelected: _wrapLines,
            onPressed: widget.diff.trim().isEmpty
                ? null
                : () {
                    if (_horizontal.hasClients) _horizontal.jumpTo(0);
                    setState(() => _wrapLines = !_wrapLines);
                  },
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: _wrapLines ? colors.surfaceOverlay : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(RecodexIcons.wrapText, size: 18),
          ),
          IconButton(
            tooltip: _copied ? '已复制' : '复制补丁',
            onPressed: widget.diff.trim().isEmpty ? null : _copyPatch,
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            icon: Icon(
              _copied ? RecodexIcons.check : RecodexIcons.copy,
              size: 17,
              color: _copied ? colors.success : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCode(
    BuildContext context,
    double viewportWidth,
    double gutter,
    TextStyle style,
  ) {
    var contentWidth = viewportWidth;
    if (!_wrapLines) {
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      );
      for (final line in _lines) {
        painter.text = TextSpan(text: _displayText(line), style: style);
        painter.layout();
        contentWidth = math.max(contentWidth, painter.width + gutter * 2 + 48);
      }
      painter.dispose();
    }
    // One width for every row keeps backgrounds continuous across the viewport
    // and across the horizontal extent of the longest source line.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SelectionArea(
        child: Scrollbar(
          controller: _vertical,
          notificationPredicate: (event) => event.metrics.axis == Axis.vertical,
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: contentWidth > viewportWidth,
            notificationPredicate: (event) =>
                event.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: ListView.builder(
                  controller: _vertical,
                  primary: false,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) => _DiffRow(
                    line: _lines[index],
                    gutter: gutter,
                    style: style,
                    wrap: _wrapLines,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.line,
    required this.gutter,
    required this.style,
    required this.wrap,
  });

  final DiffLine line;
  final double gutter;
  final TextStyle style;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final tone = switch (line.kind) {
      DiffLineKind.addition => colors.success,
      DiffLineKind.deletion => colors.error,
      _ => null,
    };
    final isHunk = line.kind == DiffLineKind.hunk;
    final isMetadata = line.kind == DiffLineKind.metadata;
    final background =
        tone?.withValues(alpha: 0.09) ??
        (isHunk
            ? colors.surfaceOverlay.withValues(alpha: 0.65)
            : Colors.transparent);
    final foreground = tone == null
        ? colors.text
        : Color.lerp(tone, colors.text, 0.3)!;
    return ColoredBox(
      color: background,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: isHunk ? 7 : 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionContainer.disabled(
              child: Row(
                children: [
                  for (final number in [line.oldNumber, line.newNumber])
                    SizedBox(
                      width: gutter,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          number?.toString() ?? '',
                          textAlign: TextAlign.right,
                          style: style.copyWith(color: colors.textMuted),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 24,
                    child: Text(
                      line.marker,
                      textAlign: TextAlign.center,
                      style: style.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Text(
                  _displayText(line),
                  softWrap: wrap,
                  style: style.copyWith(
                    color: isHunk || isMetadata ? colors.textMuted : foreground,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayText(DiffLine line) =>
    line.text.isEmpty ? ' ' : line.text.replaceAll('\t', '    ');

class _DiffEmptyState extends StatelessWidget {
  const _DiffEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(RecodexIcons.fileText, color: colors.textMuted, size: 28),
            const SizedBox(height: 12),
            Text(
              '暂无可显示的修改内容',
              style: TextStyle(
                color: colors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请返回对话刷新任务后重试。\n二进制文件可能只有变更记录。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffStat {
  const _DiffStat({required this.added, required this.removed});
  final int added;
  final int removed;
}

_DiffStat? _fileStat(GitSnapshot? snapshot, String path) {
  if (snapshot == null) return null;
  final resolved = snapshot.resolveFilePath(path);
  for (final line in snapshot.numstat.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3 || parts.sublist(2).join('\t') != resolved) continue;
    final added = int.tryParse(parts[0]);
    final removed = int.tryParse(parts[1]);
    if (added == null || removed == null) return null;
    return _DiffStat(added: added, removed: removed);
  }
  return null;
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}
