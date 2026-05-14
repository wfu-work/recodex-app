import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../models/bridge_models.dart';
import '../../theme/recodex_theme.dart';
import 'bridge_controller.dart';

class GitDiffPageArgs {
  const GitDiffPageArgs({required this.snapshot, required this.selectedPath});

  final GitSnapshot? snapshot;
  final String selectedPath;
}

class GitDiffPage extends StatelessWidget {
  const GitDiffPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments is GitDiffPageArgs
        ? Get.arguments as GitDiffPageArgs
        : const GitDiffPageArgs(snapshot: null, selectedPath: '');
    final controller = Get.isRegistered<BridgeController>()
        ? Get.find<BridgeController>()
        : null;

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: 'Git Diff'),
        body: SafeArea(
          top: false,
          child: Obx(() {
            final liveSnapshot = controller?.gitSnapshot.value;
            final snapshot = (liveSnapshot?.diff.trim().isNotEmpty ?? false)
                ? liveSnapshot
                : args.snapshot;
            final resolvedPath = _resolveDiffPath(
              snapshot?.numstat ?? '',
              args.selectedPath,
            );
            final diff = _extractFileDiff(
              snapshot?.diff ?? '',
              resolvedPath,
            ).trim();
            final stat = _fileStat(snapshot?.numstat ?? '', resolvedPath);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                _DiffFileHeader(
                  path: resolvedPath,
                  branch: snapshot?.branch,
                  stat: stat,
                ),
                const SizedBox(height: 14),
                _DiffCodePanel(
                  diff: diff,
                  fallback: _fallbackDiffText(snapshot, resolvedPath),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _DiffFileHeader extends StatelessWidget {
  const _DiffFileHeader({required this.path, required this.branch, this.stat});

  final String path;
  final String? branch;
  final _DiffStat? stat;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.assistantBubble.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(alpha: 0.12),
            offset: const Offset(0, 18),
            blurRadius: 34,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.icon.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.icon.withValues(alpha: 0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.difference_outlined, color: colors.icon),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _baseName(path).isEmpty ? 'Git Diff' : _baseName(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if ((branch ?? '').trim().isNotEmpty) branch!.trim(),
                      if (path.trim().isNotEmpty) path.trim(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (stat != null) ...[
              const SizedBox(width: 12),
              _DeltaPill(added: stat!.added, removed: stat!.removed),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.added, required this.removed});

  final int added;
  final int removed;

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '+$added',
                style: TextStyle(color: colors.success),
              ),
              const TextSpan(text: '  '),
              TextSpan(
                text: '-$removed',
                style: TextStyle(color: colors.error),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _DiffCodePanel extends StatelessWidget {
  const _DiffCodePanel({required this.diff, required this.fallback});

  final String diff;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final lines = diff.isEmpty ? const <String>[] : diff.split('\n');
    final content = diff.isEmpty
        ? _DiffEmptyState(message: fallback)
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < lines.length; index++)
                  _DiffLine(line: lines[index], number: index + 1),
              ],
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff10141d).withValues(alpha: 0.92)
            : const Color(0xfffbfcff).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(alpha: 0.14),
            offset: const Offset(0, 18),
            blurRadius: 36,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(24), child: content),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, required this.number});

  final String line;
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final style = _lineStyle(context, line);
    return Container(
      constraints: const BoxConstraints(minWidth: 680),
      color: style.background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$number',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colors.textMuted.withValues(alpha: 0.56),
                fontSize: 12,
                height: 1.45,
                fontFamily: 'Menlo',
              ),
            ),
          ),
          const SizedBox(width: 14),
          SelectableText(
            line.isEmpty ? ' ' : line,
            style: TextStyle(
              color: style.foreground,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: style.bold ? FontWeight.w800 : FontWeight.w600,
              fontFamily: 'Menlo',
              fontFamilyFallback: const [
                'SF Mono',
                'Monaco',
                'Consolas',
                'monospace',
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffEmptyState extends StatelessWidget {
  const _DiffEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
      child: Column(
        children: [
          Icon(Icons.manage_search_outlined, color: colors.textMuted, size: 34),
          const SizedBox(height: 12),
          SelectableText(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineStyle {
  const _LineStyle({
    required this.foreground,
    required this.background,
    this.bold = false,
  });

  final Color foreground;
  final Color background;
  final bool bold;
}

class _DiffStat {
  const _DiffStat({required this.added, required this.removed});

  final int added;
  final int removed;
}

_LineStyle _lineStyle(BuildContext context, String line) {
  final colors = context.recodexColors;
  final transparent = Colors.transparent;
  if (line.startsWith('+++') || line.startsWith('---')) {
    return _LineStyle(foreground: colors.textMuted, background: transparent);
  }
  if (line.startsWith('+')) {
    return _LineStyle(
      foreground: colors.success,
      background: colors.success.withValues(alpha: 0.12),
    );
  }
  if (line.startsWith('-')) {
    return _LineStyle(
      foreground: colors.error,
      background: colors.error.withValues(alpha: 0.12),
    );
  }
  if (line.startsWith('@@')) {
    return _LineStyle(
      foreground: colors.icon,
      background: colors.icon.withValues(alpha: 0.10),
      bold: true,
    );
  }
  if (line.startsWith('diff --git') || line.startsWith('index ')) {
    return _LineStyle(
      foreground: colors.textMuted,
      background: colors.surfaceOverlay.withValues(alpha: 0.34),
      bold: true,
    );
  }
  return _LineStyle(foreground: colors.text, background: transparent);
}

String _extractFileDiff(String diff, String path) {
  final trimmedPath = path.trim();
  if (diff.trim().isEmpty || trimmedPath.isEmpty) return '';
  final lines = diff.split('\n');
  final buffer = StringBuffer();
  var collecting = false;

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      final belongsToFile = _diffHeaderMatchesPath(line, trimmedPath);
      if (collecting && !belongsToFile) break;
      collecting = belongsToFile;
    }
    if (collecting) {
      buffer.writeln(line);
    }
  }

  return buffer.toString();
}

bool _diffHeaderMatchesPath(String line, String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = _baseName(normalized);
  final headerPaths = _diffHeaderPaths(line);
  return line.contains(' a/$normalized ') ||
      line.endsWith(' a/$normalized') ||
      line.contains(' b/$normalized') ||
      line.endsWith(' b/$normalized') ||
      headerPaths.any((candidate) => _baseName(candidate) == name);
}

_DiffStat? _fileStat(String numstat, String path) {
  final normalized = path.replaceAll('\\', '/').trim();
  final name = _baseName(normalized);
  for (final line in numstat.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final filePath = parts.sublist(2).join('\t').replaceAll('\\', '/').trim();
    if (filePath != normalized && _baseName(filePath) != name) continue;
    return _DiffStat(
      added: int.tryParse(parts[0]) ?? 0,
      removed: int.tryParse(parts[1]) ?? 0,
    );
  }
  return null;
}

String _resolveDiffPath(String numstat, String path) {
  final normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return normalized;
  final name = _baseName(normalized);
  for (final line in numstat.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final filePath = parts.sublist(2).join('\t').replaceAll('\\', '/').trim();
    if (filePath == normalized || _baseName(filePath) == name) {
      return filePath;
    }
  }
  return normalized;
}

List<String> _diffHeaderPaths(String line) {
  if (!line.startsWith('diff --git ')) return const [];
  return line
      .split(RegExp(r'\s+'))
      .skip(2)
      .map((part) => part.replaceFirst(RegExp(r'^[ab]/'), ''))
      .where((part) => part.isNotEmpty)
      .toList();
}

String _fallbackDiffText(GitSnapshot? snapshot, String path) {
  if (snapshot == null) return '暂无 Git diff 数据。请稍等刷新完成后再查看。';
  final parts = <String>[
    if (path.trim().isNotEmpty) '未找到 $path 的详细 diff。',
    if ((snapshot.diff).trim().isEmpty) '当前快照没有包含具体 diff 内容。',
    if (snapshot.stat.trim().isNotEmpty) snapshot.stat.trim(),
    if (snapshot.numstat.trim().isNotEmpty) snapshot.numstat.trim(),
  ];
  if (parts.isEmpty) return '当前没有可显示的 Git diff。';
  return parts.join('\n\n');
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}
