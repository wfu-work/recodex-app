// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/answer_footer.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _ThemeController extends ThemeController {
  @override
  void onInit() {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<ThemeController>(_ThemeController(), permanent: true);
  });
  tearDown(Get.reset);

  Widget page(Widget child) => MaterialApp(
    theme: RecodexTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  final end = DateTime(2026, 9, 10, 17, 20, 30);
  List<SessionEvent> answer(String text, int total) => [
    SessionEvent(kind: 'assistant', text: text),
    SessionEvent(
      kind: 'done',
      text: '',
      completedAt: end,
      durationMs: 65000,
      usage: TokenUsage(
        inputTokens: total - 10,
        outputTokens: 10,
        totalTokens: total,
        scope: TokenUsageScope.turn,
      ),
    ),
  ];

  testWidgets('each answer copies only its own visible Markdown body', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const body = '**已完成**，参见 [main.dart](/project/main.dart)。';
    await tester.pumpWidget(
      page(
        Column(
          children: [
            AssistantAnswerBlock(
              events: [
                const SessionEvent(kind: 'reasoning', text: '私有思考内容'),
                const SessionEvent(kind: 'tool_call', text: 'npm test 工具输出'),
                ...answer(body, 1234),
                const SessionEvent(
                  kind: 'file_change',
                  text: '1\t2\tmain.dart',
                  fileDiffs: {'main.dart': '@@ -1 +1 @@\n-old\n+new'},
                ),
              ],
              completed: true,
            ),
            AssistantAnswerBlock(
              events: answer('第二条回答', 5678),
              completed: true,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(AnswerFooter), findsNWidgets(2));
    final copy = find.byKey(const ValueKey('copy-answer'));
    await tester.ensureVisible(copy.first);
    await tester.tap(copy.first);
    await tester.pump();
    expect(copied, [body]);
    expect(find.byTooltip('已复制'), findsOneWidget);
    await tester.ensureVisible(copy.last);
    await tester.tap(copy.last);
    await tester.pump();
    expect(copied, [body, '第二条回答']);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byTooltip('复制回答'), findsNWidgets(2));
  });

  testWidgets(
    'completed footer shows tokens, duration and local completion time',
    (tester) async {
      await tester.pumpWidget(
        page(
          AssistantAnswerBlock(
            events: answer('内容', 1234),
            completed: true,
            status: TimelineTaskStatus.completed,
          ),
        ),
      );
      expect(find.text('Token 1,234'), findsOneWidget);
      expect(find.text('耗时 1分钟 5秒'), findsOneWidget);
      expect(find.text('完成 2026/09/10 17:20:30'), findsOneWidget);
      await tester.tap(find.text('Token 1,234'));
      await tester.pumpAndSettle();
      expect(find.textContaining('输入 1,224 · 输出 10'), findsOneWidget);
    },
  );

  testWidgets(
    'unknown statistics show missing values, never zero or current time',
    (tester) async {
      await tester.pumpWidget(
        page(
          const AssistantAnswerBlock(
            events: [SessionEvent(kind: 'assistant', text: '历史回答')],
            completed: true,
          ),
        ),
      );
      expect(find.text('Token 未提供'), findsOneWidget);
      expect(find.text('耗时 未记录'), findsOneWidget);
      expect(find.text('完成时间未记录'), findsOneWidget);
      expect(find.byTooltip('复制回答'), findsOneWidget);
    },
  );

  testWidgets(
    'shows cached input as part of input rather than adding it again',
    (tester) async {
      await tester.pumpWidget(
        page(
          const AnswerFooter(
            text: '回答',
            showMetrics: true,
            usage: TokenUsage(
              inputTokens: 276669,
              outputTokens: 3902,
              totalTokens: 280571,
              cachedInputTokens: 175232,
              reasoningOutputTokens: 2129,
              scope: TokenUsageScope.turn,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Token 280,571'));
      await tester.pumpAndSettle();
      expect(find.textContaining('输入中含缓存 175,232'), findsOneWidget);
      expect(find.textContaining('输出中含推理 2,129'), findsOneWidget);
      expect(find.textContaining('总计 280,571 Token'), findsOneWidget);
    },
  );

  testWidgets('active usage wraps on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      page(
        AssistantAnswerBlock(
          events: answer('部分回答', 1234567),
          completed: false,
          status: TimelineTaskStatus.processing,
        ),
      ),
    );
    expect(find.text('Token 1,234,567'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('metrics preference keeps copy available', (tester) async {
    await tester.pumpWidget(
      page(
        AssistantAnswerBlock(
          events: answer('内容', 1234),
          completed: true,
          showUsageMetrics: false,
        ),
      ),
    );
    expect(find.byTooltip('复制回答'), findsOneWidget);
    expect(find.text('Token 1,234'), findsNothing);
    expect(find.textContaining('17:20:30'), findsNothing);
    expect(find.textContaining('耗时'), findsNothing);
  });

  testWidgets(
    'explicit active or unknown status overrides a stale completion',
    (tester) async {
      for (final status in [
        TimelineTaskStatus.processing,
        TimelineTaskStatus.unknown,
        TimelineTaskStatus.loading,
      ]) {
        await tester.pumpWidget(
          page(
            AssistantAnswerBlock(
              events: answer('部分输出', 1234),
              completed: true,
              status: status,
            ),
          ),
        );
        expect(find.byType(AnswerFooter), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('narrow screens and enlarged text wrap long metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Get.find<ThemeController>().fontScale.value = 1.4;
    await tester.pumpWidget(
      page(
        AssistantAnswerBlock(
          events: answer('已完成', 123456789012),
          completed: true,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Token 123,456,789,012'), findsOneWidget);
    expect(find.text('完成 2026/09/10 17:20:30'), findsOneWidget);
  });

  testWidgets('clipboard failure is reported and can be retried', (
    tester,
  ) async {
    var fails = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' && fails) {
          throw PlatformException(code: 'clipboard-unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      page(AssistantAnswerBlock(events: answer('内容', 1), completed: true)),
    );
    await tester.tap(find.byTooltip('复制回答'));
    await tester.pump();
    expect(find.text('复制失败，请重试'), findsOneWidget);
    fails = false;
    await tester.tap(find.byTooltip('复制回答'));
    await tester.pump();
    expect(find.byTooltip('已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
