import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('shares Codex switch colors across light and dark themes', (
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
      expect(theme.switchTheme.thumbColor?.resolve({}), Colors.white);
      expect(
        theme.switchTheme.trackColor?.resolve({}),
        theme.extension<RecodexThemeColors>()!.text.withValues(alpha: 0.1),
      );
    }
  });

  testWidgets('keeps a generous touch target around the compact Codex pill', (
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

    expect(tester.getSize(find.byType(CodexSwitch)), const Size(44, 44));
    expect(find.byType(Switch), findsOneWidget);

    final track = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('codex-switch-track')),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('codex-switch-track'))),
      const Size(32, 20),
    );
    expect(
      (track.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(10),
    );
  });

  testWidgets('switch supports touch, keyboard, and accessible toggle state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return CodexSwitch(
                  value: value,
                  onChanged: enabled
                      ? (next) => setState(() => value = next)
                      : null,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(Switch)),
      matchesSemantics(
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    // The space around the visible pill remains tappable.
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodexSwitch)) + const Offset(3, 3),
    );
    await tester.pumpAndSettle();
    expect(value, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(value, isFalse);

    rebuild(() => enabled = false);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CodexSwitch));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(value, isFalse);
    expect(
      tester.getSemantics(find.byType(Switch)),
      matchesSemantics(hasEnabledState: true, hasToggledState: true),
    );
    semantics.dispose();
  });
}
