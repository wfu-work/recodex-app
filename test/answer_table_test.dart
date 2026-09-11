// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/answer_table.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _Theme extends ThemeController {
  @override
  void onInit() {}
}

const _table = r'''| 功能 | 使用方式 | 优先级 | 难度 |
| --- | --- | :---: | ---: |
| **图片、截图** | 手机选择相册或拍照；电脑端支持选择、粘贴和拖入图片 | 第一阶段 | 中等 |
| 引用工作区文件 | 搜索电脑当前项目中的文件，与 `@files` 共用入口 | 第二阶段 | 中等 |
| 选择 Skills | 展示当前电脑可用的技能，与 `$skills` 共用入口 | 第二阶段 | 中等，需要验证接口 |
| 上传普通文件 | 上传日志、代码、文本，后续扩展 PDF 等格式 | 第三阶段 | 中等偏高 |''';

Widget _answer(
  String text, {
  double width = 360,
  bool dark = true,
  double scale = 1,
}) => MaterialApp(
  theme: (dark ? RecodexTheme.dark : RecodexTheme.light).copyWith(
    platform: TargetPlatform.android,
  ),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: AssistantAnswerBlock(
              completed: true,
              showReasoning: false,
              showUsageMetrics: false,
              events: [SessionEvent(kind: 'assistant', text: text)],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<ThemeController>(_Theme());
  });
  tearDown(Get.reset);

  for (final dark in [false, true]) {
    testWidgets('answer renders a scrollable mobile table, dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(_answer('建议如下：\n\n$_table\n\n继续说明。', dark: dark));
      await tester.pumpAndSettle();
      expect(find.byType(AnswerTable), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('继续说明。'), findsOneWidget);
      expect(find.textContaining('| ---'), findsNothing);
      expect(find.text('@files'), findsOneWidget);
      expect(find.text(r'$skills'), findsOneWidget);
      expect(find.text('左右滑动查看完整表格'), findsOneWidget);
      final scroll = find.byKey(
        const ValueKey('answer-table-horizontal-scroll'),
      );
      final controller = tester
          .widget<SingleChildScrollView>(scroll)
          .controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      await tester.timedDragFrom(
        tester.getTopLeft(scroll) + const Offset(300, 24),
        const Offset(-260, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(find.text('中等偏高').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('table adapts to narrow screens, landscape and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in [1.0, 2.0]) {
      for (final width in [280.0, 360.0, 740.0, 960.0]) {
        await tester.pumpWidget(_answer(_table, width: width, scale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width at $scale');
        final viewport = find.descendant(
          of: find.byType(AnswerTable),
          matching: find.byType(SingleChildScrollView),
        );
        expect(tester.getSize(viewport).width, lessThanOrEqualTo(width));
        expect(find.text('上传普通文件'), findsOneWidget);
        if (width == 960 && scale == 1) {
          expect(find.text('左右滑动查看完整表格'), findsNothing);
        }
      }
    }
  });

  testWidgets(
    'incomplete streamed table becomes a table without losing surrounding content',
    (tester) async {
      const header = '前面的文字\n\n| 功能 | 说明 |\n| --- |';
      await tester.pumpWidget(_answer(header));
      expect(find.byType(AnswerTable), findsNothing);
      await tester.pumpWidget(_answer('$header --- |\n| 上传 | 进行中 |'));
      await tester.pumpAndSettle();
      expect(find.byType(AnswerTable), findsOneWidget);
      expect(find.text('前面的文字'), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);
      await tester.pumpWidget(_answer('$header --- |\n| 上传 | 完成 |\n\n后面的文字'));
      await tester.pumpAndSettle();
      expect(find.text('进行中'), findsNothing);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('后面的文字'), findsOneWidget);
    },
  );

  testWidgets(
    'code fences preserve literal tables and answer tables keep inline file labels',
    (tester) async {
      for (final fence in ['```', '~~~']) {
        await tester.pumpWidget(
          _answer(
            '$fence\n$_table\n$fence\n\n名称 | 文件\n--- | ---\n入口 | [app.dart](/work/app.dart:42)',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AnswerTable), findsOneWidget);
        expect(find.widgetWithText(SelectableText, _table), findsOneWidget);
        expect(find.text('app.dart'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
