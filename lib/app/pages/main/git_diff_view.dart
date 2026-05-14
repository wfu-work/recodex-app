import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../models/bridge_models.dart';
import '../../theme/recodex_theme.dart';

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
    final colors = context.recodexColors;
    final snapshot = args.snapshot;
    final fileDiff = _extractFileDiff(snapshot?.diff ?? '', args.selectedPath);
    final displayText = fileDiff.trim().isNotEmpty
        ? fileDiff.trim()
        : _fallbackDiffText(snapshot, args.selectedPath);

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: 'Git Diff'),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              _DiffFileHeader(
                path: args.selectedPath,
                branch: snapshot?.branch,
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.assistantBubble.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(22),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: SelectableText(
                    displayText,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 12.5,
                      height: 1.5,
                      fontFamily: 'Menlo',
                      fontFamilyFallback: const [
                        'SF Mono',
                        'Monaco',
                        'Consolas',
                        'monospace',
                      ],
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

class _DiffFileHeader extends StatelessWidget {
  const _DiffFileHeader({required this.path, required this.branch});

  final String path;
  final String? branch;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(Icons.difference_outlined, color: colors.icon),
            const SizedBox(width: 12),
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
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if ((branch ?? '').trim().isNotEmpty) branch!.trim(),
                      if (path.trim().isNotEmpty) path.trim(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  return line.contains(' a/$normalized ') ||
      line.endsWith(' a/$normalized') ||
      line.contains(' b/$normalized') ||
      line.endsWith(' b/$normalized');
}

String _fallbackDiffText(GitSnapshot? snapshot, String path) {
  if (snapshot == null) return '暂无 Git diff 数据。请先刷新 Git 状态后再打开文件。';
  final parts = <String>[
    if (path.trim().isNotEmpty) '未找到 $path 的详细 diff。',
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
