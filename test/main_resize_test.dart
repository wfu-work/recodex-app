// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/answer_footer.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/main/main_view.dart';
import 'package:recodex/app/pages/settings/settings_preferences_controller.dart';
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

class _Preferences extends SettingsPreferencesController {
  @override
  void onInit() {}
}

void main() {
  testWidgets('main timeline gives each answer its own usage baseline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Get.testMode = true;
    addTearDown(Get.reset);
    final bridge = Get.put<BridgeController>(_Bridge());
    Get.put<ThemeController>(_Theme());
    Get.put<SettingsPreferencesController>(_Preferences());
    bridge.selectedSessionId.value = 'usage';
    bridge.timelineStatus.value = TimelineTaskStatus.completed;
    bridge.events.assignAll([
      for (var i = 1; i <= 2; i++) ...[
        SessionEvent(kind: 'user', text: '问题 $i', turnId: '$i'),
        SessionEvent(kind: 'assistant', text: '回答 $i', turnId: '$i'),
        SessionEvent(
          kind: 'done',
          text: '',
          turnId: '$i',
          usage: TokenUsage(
            inputTokens: i * 1000,
            outputTokens: i * 100,
            totalTokens: i * 1100,
            scope: TokenUsageScope.thread,
          ),
        ),
      ],
    ]);
    await tester.pumpWidget(
      GetMaterialApp(theme: RecodexTheme.light, home: const MainPage()),
    );
    await tester.pumpAndSettle();
    final footer = tester
        .widgetList<AnswerFooter>(find.byType(AnswerFooter))
        .singleWhere((widget) => widget.text == '回答 2');
    expect(footer.usage?.scope, TokenUsageScope.turn);
    expect(footer.usage?.totalTokens, 1100);

    bridge.events.add(const SessionEvent(kind: 'git_change', text: '',
      turnId: '1', itemId: 'turn-diff:1',
      fileDiffs: {'previous.dart': '@@ -0,0 +1 @@\n+previous'},
    ));
    bridge.timelineRevision.value++;
    await tester.pumpAndSettle();
    final currentAnswer = tester.widgetList<AssistantAnswerBlock>(
      find.byType(AssistantAnswerBlock),
    ).singleWhere((answer) => answer.events.any((event) => event.text == '回答 2'));
    expect(currentAnswer.events.every((event) => event.turnId == '2'), isTrue);
    expect(currentAnswer.gitChangeSummary, isNull);

    // A response without statistics must break the chain of baselines.
    bridge.events.insertAll(3, [
      const SessionEvent(kind: 'user', text: '缺少统计的问题', turnId: 'missing'),
      const SessionEvent(kind: 'assistant', text: '缺少统计的回答', turnId: 'missing'),
      const SessionEvent(kind: 'done', text: '', turnId: 'missing'),
    ]);
    bridge.timelineRevision.value++;
    await tester.pumpAndSettle();
    final afterGap = tester
        .widgetList<AnswerFooter>(find.byType(AnswerFooter))
        .singleWhere((widget) => widget.text == '回答 2');
    expect(afterGap.usage, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final running in [false, true]) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
        'main resize with running=$running and reduceMotion=$reduceMotion',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1100, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          Get.testMode = true;
          final bridge = Get.put<BridgeController>(_Bridge());
          Get.put<ThemeController>(_Theme());
          final preferences = Get.put<SettingsPreferencesController>(
            _Preferences(),
          );
          preferences.reduceAnimations.value = reduceMotion;
          addTearDown(Get.reset);
          bridge.selectedSessionId.value = 'resize';
          bridge.currentSessionId.value = running ? 'resize' : null;
          bridge.timelineStatus.value = running
              ? TimelineTaskStatus.processing
              : TimelineTaskStatus.completed;
          bridge.events.assignAll([
            for (var i = 0; i < 12; i++) ...[
              SessionEvent(kind: 'user', text: '检查窗口变化 $i', turnId: '$i'),
              SessionEvent(
                kind: 'assistant',
                turnId: '$i',
                text: List.filled(
                  12,
                  '窗口变窄时文字需要重新换行，内容高度会随可用宽度变化。',
                ).join('\n\n'),
              ),
              if (i < 11 || !running)
                SessionEvent(kind: 'done', text: '', turnId: '$i'),
            ],
          ]);
          await tester.pumpWidget(
            GetMaterialApp(theme: RecodexTheme.light, home: const MainPage()),
          );
          for (var frame = 0; frame < 30; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(tester.takeException(), isNull);
          final scroll = tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
          expect(scroll.position.pixels, greaterThan(0));
          for (final width in [
            900.0,
            760.0,
            600.0,
            460.0,
            360.0,
            320.0,
            1100.0,
            460.0,
          ]) {
            if (running) {
              bridge.events.add(
                const SessionEvent(
                  kind: 'assistant',
                  text: '增量输出',
                  turnId: '11',
                ),
              );
              bridge.timelineRevision.value++;
            }
            tester.view.physicalSize = Size(width, 900);
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull, reason: 'resize to $width');
            await tester.pump(const Duration(milliseconds: 80));
            expect(
              tester.takeException(),
              isNull,
              reason: 'scroll after resize to $width',
            );
          }
          // Force a lazy-list extent correction and then exercise scrolling
          // again: the position must remain usable after repeated resizes.
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
          expect(tester.takeException(), isNull);
          final previous = scroll.offset;
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 250),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(scroll.offset, lessThan(previous));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        },
        variant: TargetPlatformVariant({TargetPlatform.macOS}),
      );
    }
  }
}
