import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/routes/app_pages.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(ThemeController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('opens theme settings as a route', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        getPages: AppPages.routes,
        initialRoute: Routes.theme,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主题设置'), findsOneWidget);
    expect(find.text('界面模式'), findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色模式'), findsOneWidget);
    expect(find.text('深色模式'), findsOneWidget);
  });

  testWidgets('applies both mode and accent choices immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = Get.find<ThemeController>();
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        getPages: AppPages.routes,
        initialRoute: Routes.theme,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(controller.preference.value, RecodexThemePreference.dark);

    await tester.tap(find.text('松石青'));
    await tester.pumpAndSettle();
    expect(controller.accent.value, RecodexThemeAccent.jade);
  });
}
