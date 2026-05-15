import '../../../models/bridge_models.dart';

String lastPathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final normalized = trimmed.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? trimmed : parts.last;
}

class GitChangeOverview {
  const GitChangeOverview({
    required this.changedFiles,
    required this.addedLines,
    required this.removedLines,
  });

  final int changedFiles;
  final int addedLines;
  final int removedLines;

  bool get isClean => changedFiles == 0 && addedLines == 0 && removedLines == 0;
}

GitChangeOverview parseGitChangeOverview(GitSnapshot? snapshot) {
  if (snapshot == null) {
    return const GitChangeOverview(
      changedFiles: 0,
      addedLines: 0,
      removedLines: 0,
    );
  }
  var addedLines = 0;
  var removedLines = 0;
  final changedPaths = <String>{};

  for (final line in snapshot.numstat.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final path = parts.sublist(2).join('\t').trim();
    if (path.isEmpty) continue;
    changedPaths.add(path);
    final added = int.tryParse(parts[0]) ?? 0;
    final removed = int.tryParse(parts[1]) ?? 0;
    addedLines += added;
    removedLines += removed;
  }

  if (changedPaths.isNotEmpty) {
    return GitChangeOverview(
      changedFiles: changedPaths.length,
      addedLines: addedLines,
      removedLines: removedLines,
    );
  }

  for (final line in snapshot.status.split('\n')) {
    if (line.length < 3) continue;
    final path = line.substring(3).trim();
    if (path.isEmpty) continue;
    changedPaths.add(path);
  }

  return GitChangeOverview(
    changedFiles: changedPaths.length,
    addedLines: 0,
    removedLines: 0,
  );
}
