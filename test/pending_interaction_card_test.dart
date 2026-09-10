// ignore_for_file: must_call_super
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/models/pending_interaction.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/main/main_view.dart';
import 'package:recodex/app/pages/main/widget/pending_interaction_card.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _Bridge extends BridgeController {
  @override
  void onInit() {}
  @override
  void startLiveTimelineRefresh() {}
  @override
  void stopLiveTimelineRefresh() {}
}

class _Theme extends ThemeController {
  @override
  void onInit() {}
}

void main() {
  testWidgets(
    'questions require all answers, mask secrets, and disable resubmission',
    (tester) async {
      Map<String, dynamic>? response;
      final item = PendingInteraction.fromJson({
        'approvalId': 'question',
        'kind': 'userInput',
        'canRespond': true,
        'params': {
          'threadId': 'task',
          'questions': [
            {
              'id': 'choice',
              'question': '部署方式',
              'isOther': true,
              'options': [
                {'label': '本地', 'description': '本机运行'},
                {'label': '远程'},
              ],
            },
            {'id': 'secret', 'question': '密钥', 'isSecret': true},
          ],
        },
      });
      Widget view(bool submitted) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PendingInteractionCard(
              item: item,
              enabled: true,
              submitted: submitted,
              onRespond: (value) => response = value,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(false));
      await tester.tap(find.text('提交回答'));
      await tester.pump();
      expect(response, isNull);
      expect(find.text('请回答此问题'), findsNWidgets(2));
      await tester.tap(find.text('本地'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'fixture-secret');
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        true,
      );
      await tester.tap(find.text('提交回答'));
      await tester.pump();
      expect(response, {
        'answers': {
          'choice': {
            'answers': ['本地'],
          },
          'secret': {
            'answers': ['fixture-secret'],
          },
        },
      });
      await tester.pumpWidget(view(true));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('已提交，等待确认…'), findsOneWidget);
    },
  );

  testWidgets('desktop-only approval exposes details without remote action', (
    tester,
  ) async {
    final item = PendingInteraction.fromJson({
      'approvalId': 'approval',
      'kind': 'approval',
      'method': 'item/commandExecution/requestApproval',
      'canRespond': false,
      'params': {
        'threadId': 'task',
        'command': 'git status',
        'cwd': '/workspace',
        'reason': 'check changes',
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingInteractionCard(
            item: item,
            enabled: true,
            submitted: false,
            onRespond: (_) => fail('must not respond'),
          ),
        ),
      ),
    );
    expect(find.text('命令：git status'), findsOneWidget);
    expect(find.text('请在 Codex 桌面端处理，处理结果会自动同步。'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets(
    'running task keeps editable drafts isolated across task switches',
    (tester) async {
      Get.testMode = true;
      final bridge = Get.put<BridgeController>(_Bridge());
      Get.put<ThemeController>(_Theme());
      addTearDown(Get.reset);
      bridge.connected.value = true;
      bridge.selectedWorkspace.value = const WorkspaceInfo(
        id: 'project',
        name: 'project',
        path: '/tmp/project',
      );
      bridge.selectedSessionId.value = 'first';
      bridge.timelineStatus.value = TimelineTaskStatus.processing;
      await tester.pumpWidget(
        GetMaterialApp(theme: RecodexTheme.light, home: const MainPage()),
      );
      final input = find.byType(TextField);
      await tester.enterText(input, '第一任务的草稿');
      expect(tester.widget<TextField>(input).readOnly, false);
      expect(find.byTooltip('补充到当前任务'), findsOneWidget);
      expect(find.byTooltip('停止任务'), findsOneWidget);
      bridge.selectedSessionId.value = 'second';
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.enterText(input, '第二任务的草稿');
      bridge.selectedSessionId.value = 'first';
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, '第一任务的草稿');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
