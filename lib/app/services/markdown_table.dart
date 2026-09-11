enum MarkdownTableAlignment { left, center, right }

/// A pipe table within an answer. Recognition requires a complete header and
/// delimiter row so ordinary prose and incomplete streamed headers stay text.
class MarkdownTable {
  const MarkdownTable({
    required this.headers,
    required this.rows,
    required this.alignments,
    required this.endLine,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<MarkdownTableAlignment> alignments;
  final int endLine;

  static MarkdownTable? tryParse(List<String> lines, int startLine) {
    if (startLine < 0 || startLine + 1 >= lines.length) return null;
    final headers = _splitRow(lines[startLine]);
    final separators = _splitRow(lines[startLine + 1]);
    if (headers == null ||
        separators == null ||
        headers.length != separators.length ||
        !separators.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
      return null;
    }
    final alignments = separators
        .map((cell) {
          if (cell.startsWith(':') && cell.endsWith(':')) {
            return MarkdownTableAlignment.center;
          }
          return cell.endsWith(':')
              ? MarkdownTableAlignment.right
              : MarkdownTableAlignment.left;
        })
        .toList(growable: false);
    final rows = <List<String>>[];
    var endLine = startLine + 2;
    while (endLine < lines.length) {
      final line = lines[endLine].trimLeft();
      // A new Markdown block ends a table even when no blank line precedes it.
      if (RegExp(
        r'^(?:`{3,}|~{3,}|#{1,6}\s|>|[-*+]\s|\d+[.)]\s)',
      ).hasMatch(line)) {
        break;
      }
      final cells = _splitRow(line);
      if (cells == null) break;
      rows.add(
        List.generate(
          headers.length,
          (column) => column < cells.length ? cells[column] : '',
        ),
      );
      endLine += 1;
    }
    return MarkdownTable(
      headers: headers,
      rows: rows,
      alignments: alignments,
      endLine: endLine,
    );
  }

  static List<String>? _splitRow(String source) {
    final line = source.trim();
    if (line.isEmpty) return null;
    final cells = <String>[];
    final cell = StringBuffer();
    var separators = 0;
    var endsWithSeparator = false;
    for (var index = 0; index < line.length; index += 1) {
      final character = line[index];
      // Preserve backslashes in paths while allowing escaped pipe characters
      // in prose and inline code (the GFM table escape convention).
      if (character == r'\' && index + 1 < line.length) {
        final next = line[index + 1];
        if (next == '|' || next == r'\') {
          cell.write(next == '|' ? '|' : r'\\');
          index += 1;
          endsWithSeparator = false;
          continue;
        }
      }
      endsWithSeparator = character == '|';
      if (endsWithSeparator) {
        separators += 1;
        cells.add(cell.toString().trim());
        cell.clear();
      } else {
        cell.write(character);
      }
    }
    if (separators == 0) return null;
    cells.add(cell.toString().trim());
    if (line.startsWith('|')) cells.removeAt(0);
    if (endsWithSeparator) cells.removeLast();
    return cells.isEmpty ? null : cells;
  }
}
