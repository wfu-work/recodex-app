// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
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
  late _Bridge bridge;

  Future<void> mount(WidgetTester tester, {bool reduceMotion = false}) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    bridge = _Bridge();
    Get.put<BridgeController>(bridge);
    Get.put<ThemeController>(_Theme());
    final preferences = Get.put<SettingsPreferencesController>(_Preferences());
    preferences.reduceAnimations.value = reduceMotion;
    bridge.selectedSessionId.value = 'stream';
    bridge.currentSessionId.value = 'stream';
    bridge.timelineStatus.value = TimelineTaskStatus.processing;
    bridge.events.assignAll([
      const SessionEvent(kind: 'user', text: '检查输入栏动画', turnId: 'turn'),
      SessionEvent(
        kind: 'assistant',
        text: List.filled(80, '任务正在持续输出，输入框应保持稳定。').join('\n'),
        turnId: 'turn',
      ),
    ]);
    await tester.pumpWidget(
      GetMaterialApp(theme: RecodexTheme.light, home: const MainPage()),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  Finder ancestor(Type type) => find
      .ancestor(of: find.byType(ComposerBar), matching: find.byType(type))
      .first;

  ScrollController scroll(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!;

  void expectVisibleAndStill(WidgetTester tester) {
    expect(
      tester.widget<AnimatedSlide>(ancestor(AnimatedSlide)).offset,
      Offset.zero,
    );
    expect(
      tester.widget<AnimatedOpacity>(ancestor(AnimatedOpacity)).opacity,
      1,
    );
    // Check intermediate frames too: an animation that hides and then reveals
    // the input would pass a final-frame-only assertion.
    expect(
      tester
          .widget<FractionalTranslation>(ancestor(FractionalTranslation))
          .translation,
      Offset.zero,
    );
    expect(
      tester.widget<FadeTransition>(ancestor(FadeTransition)).opacity.value,
      1,
    );
  }

  void appendOutput() {
    bridge.events.add(
      SessionEvent(
        kind: 'assistant',
        text: List.filled(8, '新的增量回答内容。').join('\n'),
        turnId: 'turn',
      ),
    );
    bridge.timelineRevision.value++;
  }

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'auto-follow never animates composer (reduceMotion=$reduceMotion)',
      (tester) async {
        await mount(tester, reduceMotion: reduceMotion);
        for (var frame = 0; frame < 100; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expectVisibleAndStill(tester);
        }
        final before = scroll(tester).offset;
        expect(before, greaterThan(0));
        for (var frame = 0; frame < 160; frame++) {
          if (frame % 20 == 0 && frame < 80) appendOutput();
          await tester.pump(const Duration(milliseconds: 16));
          expectVisibleAndStill(tester);
        }
        expect(scroll(tester).offset, greaterThan(before));

        final programmaticScroll = scroll(tester).animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expectVisibleAndStill(tester);
        }
        await programmaticScroll;
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manual drag and inertia animate composer despite live updates', (
    tester,
  ) async {
    await mount(tester);
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final inputPosition = tester.getCenter(find.byType(ComposerBar));
    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.widget<AnimatedSlide>(ancestor(AnimatedSlide)).offset.dy,
      greaterThan(0),
    );
    expect(
      tester.getCenter(find.byType(ComposerBar)).dy,
      greaterThan(inputPosition.dy),
    );

    appendOutput();
    for (var frame = 0; frame < 50; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.widget<AnimatedOpacity>(ancestor(AnimatedOpacity)).opacity,
        0,
      );
    }
    await gesture.up();
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expectVisibleAndStill(tester);

    // A fling's ballistic updates have no dragDetails, but still belong to
    // the user gesture. Keep the input hidden until that activity ends.
    await tester.flingFrom(const Offset(200, 300), const Offset(0, 200), 1200);
    await tester.pump(const Duration(milliseconds: 16));
    expect(scroll(tester).position.isScrollingNotifier.value, isTrue);
    expect(
      tester.widget<AnimatedOpacity>(ancestor(AnimatedOpacity)).opacity,
      0,
    );
    for (var frame = 0; frame < 300; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (!scroll(tester).position.isScrollingNotifier.value) break;
      expect(
        tester.widget<AnimatedOpacity>(ancestor(AnimatedOpacity)).opacity,
        0,
      );
    }
    expect(scroll(tester).position.isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expectVisibleAndStill(tester);

    // The explicit latest-content action is programmatic scrolling as well.
    await tester.tap(find.bySemanticsLabel('回到最新内容（任务进行中）'));
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expectVisibleAndStill(tester);
    }
    expect(tester.takeException(), isNull);
  });
}
