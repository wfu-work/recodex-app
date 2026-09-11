import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/services/markdown_table.dart';

void main() {
  test('recognizes aligned tables and leaves following prose alone', () {
    final table = MarkdownTable.tryParse([
      '说明',
      '| 功能 | 使用方式 | 优先级 |',
      '| :--- | :---: | ---: |',
      '| 图片 | 选择相册 | 第一阶段 |',
      '| 文件 | 上传日志 | 第二阶段 |',
      '',
      '继续回答',
    ], 1)!;
    expect(table.headers, ['功能', '使用方式', '优先级']);
    expect(table.alignments, MarkdownTableAlignment.values);
    expect(table.rows, [
      ['图片', '选择相册', '第一阶段'],
      ['文件', '上传日志', '第二阶段'],
    ]);
    expect(table.endLine, 5);
  });

  test('allows optional outside pipes and pads short streamed rows', () {
    final table = MarkdownTable.tryParse([
      '功能 | 描述 | 状态',
      '--- | --- | ---',
      '图片 | 上传中',
      '文件 | 支持 | 完成 | 多余单元格',
      '后续说明',
    ], 0)!;
    expect(table.rows, [
      ['图片', '上传中', ''],
      ['文件', '支持', '完成'],
    ]);
    expect(table.endLine, 4);
  });

  test(
    'preserves inline formatting and escaped pipes without splitting cells',
    () {
      final table = MarkdownTable.tryParse([
        r'| 名称 | 说明 |',
        r'| --- | --- |',
        r'| **代码** | `left\|right` |',
        r'| [文件](/work/a.dart) | C:\work\a.dart |',
        r'| value | escaped\|',
      ], 0)!;
      expect(table.rows, [
        ['**代码**', '`left|right`'],
        [r'[文件](/work/a.dart)', r'C:\work\a.dart'],
        ['value', 'escaped|'],
      ]);
    },
  );

  test('does not reinterpret ordinary pipes or incomplete table headers', () {
    for (final lines in [
      ['a | b'],
      ['a | b', 'c | d'],
      ['a | b', '--- | --'],
      ['a | b', '--- | --- | ---'],
      ['---', '---'],
    ]) {
      expect(MarkdownTable.tryParse(lines, 0), isNull);
    }
    expect(
      MarkdownTable.tryParse(['| a | b |', '| --- | --- |'], 0)!.rows,
      isEmpty,
    );
  });

  test('ends tables at new blocks even without a blank line', () {
    for (final block in [
      '# next | heading',
      '- next | item',
      '1. next | item',
      '```sh',
      '~~~sh',
      '> quote | more',
    ]) {
      final table = MarkdownTable.tryParse([
        'a | b',
        '--- | ---',
        'one | two',
        block,
      ], 0)!;
      expect(table.rows, [
        ['one', 'two'],
      ]);
      expect(table.endLine, 3);
    }
  });
}
