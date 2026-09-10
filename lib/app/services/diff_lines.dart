enum DiffLineKind { context, addition, deletion, hunk, metadata }

class DiffLine {
  const DiffLine(this.text, this.kind, {this.oldNumber, this.newNumber});

  final String text;
  final DiffLineKind kind;
  final int? oldNumber;
  final int? newNumber;

  String get marker => switch (kind) {
    DiffLineKind.addition => '+',
    DiffLineKind.deletion => '−',
    _ => '',
  };

  /// Hunk coordinates refer to source lines, not positions in the patch.
  /// Track the counts too: a deleted source line may itself start with `--`.
  static List<DiffLine> parse(String patch) {
    final result = <DiffLine>[];
    final lines = patch.replaceAll('\r\n', '\n').split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final hunkPattern = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');
    var oldLine = 0;
    var newLine = 0;
    var oldRemaining = 0;
    var newRemaining = 0;
    for (final line in lines) {
      final hunk = hunkPattern.firstMatch(line);
      if (hunk != null) {
        oldLine = int.parse(hunk[1]!);
        newLine = int.parse(hunk[3]!);
        oldRemaining = int.parse(hunk[2] ?? '1');
        newRemaining = int.parse(hunk[4] ?? '1');
        result.add(DiffLine(line, DiffLineKind.hunk));
        continue;
      }
      if (line.startsWith(r'\ No newline')) {
        result.add(DiffLine(line, DiffLineKind.metadata));
        continue;
      }
      if (oldRemaining > 0 || newRemaining > 0) {
        if (line.startsWith('+') && newRemaining > 0) {
          result.add(
            DiffLine(
              line.substring(1),
              DiffLineKind.addition,
              newNumber: newLine++,
            ),
          );
          newRemaining--;
          continue;
        }
        if (line.startsWith('-') && oldRemaining > 0) {
          result.add(
            DiffLine(
              line.substring(1),
              DiffLineKind.deletion,
              oldNumber: oldLine++,
            ),
          );
          oldRemaining--;
          continue;
        }
        if (line.startsWith(' ') && oldRemaining > 0 && newRemaining > 0) {
          result.add(
            DiffLine(
              line.substring(1),
              DiffLineKind.context,
              oldNumber: oldLine++,
              newNumber: newLine++,
            ),
          );
          oldRemaining--;
          newRemaining--;
          continue;
        }
      }
      // File names already appear in the page header. Keep other metadata
      // (binary files, renames, mode changes) visible even without a hunk.
      if (line.startsWith('diff --git ') ||
          line.startsWith('index ') ||
          line.startsWith('--- ') ||
          line.startsWith('+++ ')) {
        oldRemaining = newRemaining = 0;
        continue;
      }
      result.add(DiffLine(line, DiffLineKind.metadata));
    }
    return result;
  }
}
