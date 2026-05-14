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

(int, int) parseChangedFileCounts(GitSnapshot? snapshot) {
  if (snapshot == null) return (0, 0);
  var addedFiles = 0;
  var removedFiles = 0;
  final seenAdded = <String>{};
  final seenRemoved = <String>{};

  for (final line in snapshot.numstat.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final path = parts.sublist(2).join('\t').trim();
    if (path.isEmpty) continue;
    final added = int.tryParse(parts[0]) ?? 0;
    final removed = int.tryParse(parts[1]) ?? 0;
    if (added > 0 && seenAdded.add(path)) addedFiles += 1;
    if (removed > 0 && seenRemoved.add(path)) removedFiles += 1;
  }

  if (addedFiles != 0 || removedFiles != 0) return (addedFiles, removedFiles);

  for (final line in snapshot.status.split('\n')) {
    if (line.length < 3) continue;
    final code = line.substring(0, 2);
    final path = line.substring(3).trim();
    if (path.isEmpty) continue;
    final hasAddedChange =
        code.contains('A') || code.contains('M') || code.contains('?');
    final hasRemovedChange = code.contains('D');
    if (hasAddedChange && seenAdded.add(path)) addedFiles += 1;
    if (hasRemovedChange && seenRemoved.add(path)) removedFiles += 1;
  }

  return (addedFiles, removedFiles);
}
