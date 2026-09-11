// ignore_for_file: must_call_super
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/answer_footer.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/main/git_diff_view.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/services/timeline_events.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _ThemeController extends ThemeController {
  @override
  void onInit() {}
}

class _BridgeController extends BridgeController {
  @override
  void onInit() {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<ThemeController>(_ThemeController());
  });
  tearDown(Get.reset);

  Widget page(List<SessionEvent> events, {bool done = false}) => MaterialApp(
    theme: RecodexTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: AssistantAnswerBlock(
          events: events,
          completed: done,
          collapseReasoningByDefault: false,
        ),
      ),
    ),
  );

  testWidgets('commentary stays between tools and copy contains final answer', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(const [
        SessionEvent(kind: 'assistant', text: '先检查代码', phase: 'commentary'),
        SessionEvent(kind: 'tool_call', text: '读取组件'),
        SessionEvent(kind: 'assistant', text: '找到原因了', phase: 'commentary'),
        SessionEvent(kind: 'reasoning', text: '**Preparing fix**'),
        SessionEvent(kind: 'assistant', text: '修复完成', phase: 'final_answer'),
      ], done: true),
    );
    final labels = ['先检查代码', '加载了工具读取文件', '找到原因了', 'Preparing fix', '修复完成'];
    for (var i = 1; i < labels.length; i++) {
      expect(
        tester.getTopLeft(find.text(labels[i - 1], findRichText: true)).dy,
        lessThan(
          tester.getTopLeft(find.text(labels[i], findRichText: true)).dy,
        ),
      );
    }
    expect(find.text('**Preparing fix**'), findsNothing);
    expect(tester.widget<AnswerFooter>(find.byType(AnswerFooter)).text, '修复完成');
  });

  testWidgets('recovered connection is not a live retry warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(const [
        SessionEvent(kind: 'reconnecting', text: '连接已恢复'),
        SessionEvent(kind: 'assistant', text: '继续检查', phase: 'commentary'),
      ]),
    );
    expect(find.textContaining('重新连接'), findsNothing);
    expect(find.text('连接已恢复'), findsNothing);
    expect(find.text('继续检查', findRichText: true), findsOneWidget);
  });

  test('cached late diff returns to its own turn', () {
    const a = SessionEvent(kind: 'user', text: 'A', turnId: 'a');
    const b = SessionEvent(kind: 'user', text: 'B', turnId: 'b');
    const patch = SessionEvent(
      kind: 'git_change',
      text: '',
      turnId: 'a',
      fileDiffs: {'old.dart': '@@ -0,0 +1 @@\n+old'},
    );
    const legacy = SessionEvent(kind: 'reasoning', text: '继续处理当前问题');
    final ordered = orderTimelineEvents([a, b, patch, legacy]);
    expect(ordered, [a, patch, b, legacy]);
    expect(GitSnapshot.fromEvents(ordered.skip(2)).fileDiffs, isEmpty);
  });

  test('message phase survives cache and copyWith', () {
    const message = SessionEvent(
      kind: 'assistant',
      text: '检查',
      phase: 'commentary',
    );
    expect(
      SessionEvent.fromJson(message.copyWith(text: '完成检查').toJson()).phase,
      'commentary',
    );
    expect(
      SessionEvent.fromJson({'kind': 'assistant', 'text': '旧缓存'}).phase,
      isNull,
    );
  });

  testWidgets('answer diff is not replaced by current workspace changes', (
    tester,
  ) async {
    GitSnapshot snapshot(String line) => GitSnapshot(
      branch: '',
      status: '',
      stat: '',
      numstat: '',
      diff: '',
      log: '',
      fileDiffs: {'file.dart': '@@ -0,0 +1 @@\n+$line\n'},
    );
    final bridge = Get.put<BridgeController>(_BridgeController());
    bridge.gitSnapshot.value = snapshot('workspace change');
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: GitDiffPage(
          args: GitDiffPageArgs(
            snapshot: snapshot('answer change'),
            selectedPath: 'file.dart',
            followWorkspace: false,
          ),
        ),
      ),
    );
    expect(find.text('answer change'), findsOneWidget);
    expect(find.text('workspace change'), findsNothing);
    bridge.gitSnapshot.value = snapshot('later change');
    await tester.pump();
    expect(find.text('answer change'), findsOneWidget);
    expect(find.text('later change'), findsNothing);
  });
}
