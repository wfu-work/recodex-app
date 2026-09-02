import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/settings/settings_widgets.dart';
import 'package:recodex/app/pages/settings/task_settings_view.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(BridgeController(), permanent: true);
  });

  tearDown(Get.reset);

  testWidgets('expands settings content to the available window width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      GetMaterialApp(theme: RecodexTheme.light, home: const TaskSettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(SettingsGroup).first).width, 952);

    final workspaceTrigger = find.ancestor(
      of: find.text('跟随当前配对'),
      matching: find.byType(DecoratedBox),
    );
    expect(tester.getSize(workspaceTrigger.first).width, lessThan(158));
  });
}
