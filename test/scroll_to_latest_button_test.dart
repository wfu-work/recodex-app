import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/live_activity.dart';
import 'package:recodex/app/pages/main/widget/scroll_to_latest_button.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  Widget buildButton({required bool running, VoidCallback? onPressed}) {
    return MaterialApp(
      theme: RecodexTheme.dark,
      home: Scaffold(
        body: Center(
          child: ScrollToLatestButton(
            running: running,
            reduceMotion: true,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows a down arrow and exposes the latest-content action', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      buildButton(running: false, onPressed: () => pressed = true),
    );

    expect(find.byIcon(RecodexIcons.arrowDown), findsOneWidget);
    expect(find.bySemanticsLabel('回到最新内容'), findsOneWidget);
    expect(
      tester.getSize(find.byIcon(RecodexIcons.arrowDown)),
      const Size(20, 20),
    );
    final buttonMaterial = tester.widget<Material>(
      find.descendant(
        of: find.byType(ScrollToLatestButton),
        matching: find.byType(Material),
      ),
    );
    expect(buttonMaterial.elevation, 0);
    expect(buttonMaterial.shadowColor, Colors.transparent);

    await tester.tap(find.bySemanticsLabel('回到最新内容'));
    expect(pressed, isTrue);
  });

  testWidgets('shows the shared running ripple and keeps the action', (
    tester,
  ) async {
    await tester.pumpWidget(buildButton(running: true));

    expect(find.byType(RecodexActivityRipple), findsOneWidget);
    expect(find.byIcon(RecodexIcons.arrowDown), findsNothing);
    expect(find.bySemanticsLabel('回到最新内容（任务进行中）'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });
}
