// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
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
          await tester.drag(find.byType(CustomScrollView), const Offset(0, 250));
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
