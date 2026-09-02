import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/pages/settings/conversation_display_settings_view.dart';
import 'package:recodex/app/pages/settings/settings_widgets.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(Get.reset);

  testWidgets('expands conversation display settings to the window width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        home: const ConversationDisplaySettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(SettingsGroup).first).width, 952);
  });
}
