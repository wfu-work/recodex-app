// The test controller intentionally skips the production secure-storage load.
// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/pages/main/widget/welcome_timeline.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('centers the welcome column and caps its desktop width', (
    tester,
  ) async {
    Get.testMode = true;
    Get.put<ThemeController>(_TestThemeController(), permanent: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 700,
              child: WelcomeTimeline(
                connected: true,
                connectionLabel: 'connected',
                workspaceCount: 2,
                maxWidth: 400,
                onPairing: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = find.byKey(
      const ValueKey<String>('welcome-timeline-content'),
    );
    expect(tester.getSize(content).width, closeTo(400, 0.1));
    expect(tester.getRect(content).center.dx, closeTo(350, 0.1));
    expect(find.byType(AssistantBubble), findsOneWidget);
    expect(find.byType(ToolCallRow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shrinks to a narrow conversation pane without overflow', (
    tester,
  ) async {
    Get.testMode = true;
    Get.put<ThemeController>(_TestThemeController(), permanent: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 320,
              child: WelcomeTimeline(
                connected: false,
                connectionLabel: 'connecting',
                workspaceCount: 0,
                onPairing: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = find.byKey(
      const ValueKey<String>('welcome-timeline-content'),
    );
    expect(tester.getSize(content).width, closeTo(320, 0.1));
    final cards = find.byType(FractionallySizedBox);
    expect(cards, findsNWidgets(2));
    expect(tester.getSize(cards.at(0)).width, closeTo(288, 0.1));
    expect(tester.getSize(cards.at(1)).width, closeTo(288, 0.1));
    expect(tester.takeException(), isNull);
  });
}

class _TestThemeController extends ThemeController {
  @override
  void onInit() {}
}
