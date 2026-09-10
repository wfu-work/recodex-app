import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/services/diff_lines.dart';

void main() {
  test('uses both source coordinates and resets them at each hunk', () {
    final lines = DiffLine.parse(
      '@@ -31,2 +31,4 @@\n unsafe\n+\n+import\n )\n'
      '@@ -41,3 +43,4 @@\n func\n-old\n+new\n+check\n return\n',
    );
    expect(lines.map((line) => (line.oldNumber, line.newNumber)), [
      (null, null),
      (31, 31),
      (null, 32),
      (null, 33),
      (32, 34),
      (null, null),
      (41, 43),
      (42, null),
      (null, 44),
      (null, 45),
      (43, 46),
    ]);
  });

  test(
    'handles new and deleted files, omitted counts, and no-newline notes',
    () {
      final added = DiffLine.parse(
        '@@ -0,0 +1 @@\r\n+new\r\n\\ No newline at end of file\r\n',
      );
      expect(added[1].kind, DiffLineKind.addition);
      expect(added[1].oldNumber, isNull);
      expect(added[1].newNumber, 1);
      expect(added.last.kind, DiffLineKind.metadata);
      expect(added.last.newNumber, isNull);
      final removed = DiffLine.parse('@@ -1 +0,0 @@\n-old\n');
      expect(removed[1].kind, DiffLineKind.deletion);
      expect(removed[1].oldNumber, 1);
      expect(removed[1].newNumber, isNull);
    },
  );

  test(
    'preserves source lines resembling file headers and binary metadata',
    () {
      final lines = DiffLine.parse(
        'diff --git a/a b/a\n--- a/a\n+++ b/a\n'
        '@@ -1 +1 @@\n--- source\n+++ source\n',
      );
      expect(lines, hasLength(3));
      expect(lines[1].text, '-- source');
      expect(lines[1].kind, DiffLineKind.deletion);
      expect(lines[2].text, '++ source');
      expect(lines[2].kind, DiffLineKind.addition);
      expect(
        DiffLine.parse('Binary files a/a and b/a differ').single.text,
        'Binary files a/a and b/a differ',
      );
    },
  );
}
