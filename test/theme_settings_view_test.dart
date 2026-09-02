import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/pages/settings/settings_widgets.dart';
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
    expect(find.text('黑色'), findsWidgets);
    expect(find.text('白色'), findsWidgets);
    expect(find.text('松石青'), findsNothing);
  });

  testWidgets('applies the selected display mode immediately', (tester) async {
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

    expect(controller.accent.value, RecodexThemeAccent.azure);
  });

  testWidgets('matches Codex switch dimensions and selected colors', (
    tester,
  ) async {
    final themes = <(ThemeData, Color, Color)>[
      (RecodexTheme.light, RecodexTheme.codexBlue, const Color(0xffffffff)),
      (RecodexTheme.dark, RecodexTheme.codexBlue, const Color(0xffffffff)),
    ];

    for (final (theme, trackColor, thumbColor) in themes) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(child: Switch(value: true, onChanged: (_) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(tester.getSize(switchFinder), const Size(52, 40));
      expect(
        theme.switchTheme.trackColor?.resolve({WidgetState.selected}),
        trackColor,
      );
      expect(
        theme.switchTheme.thumbColor?.resolve({WidgetState.selected}),
        thumbColor,
      );
    }
  });

  testWidgets('keeps the touch target with a controlled track radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: Center(child: CodexSwitch(value: true, onChanged: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(CodexSwitch)), const Size(52, 40));
    expect(find.byType(Switch), findsOneWidget);

    final track = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('codex-switch-track')),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('codex-switch-track'))),
      const Size(52, 28),
    );
    expect(
      (track.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(12),
    );
  });
}
