import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/live_activity.dart';
import 'package:recodex/app/pages/main/widget/scroll_to_latest_button.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  const frameKey = ValueKey('activity-frame');

  Widget buildButton({
    required bool running,
    bool reduceMotion = true,
    bool disableAnimations = false,
    bool accessibleNavigation = false,
    bool tickerEnabled = true,
    VoidCallback? onPressed,
  }) {
    return MaterialApp(
      theme: RecodexTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: TickerMode(
            enabled: tickerEnabled,
            child: RepaintBoundary(
              key: frameKey,
              child: ScrollToLatestButton(
                running: running,
                reduceMotion: reduceMotion,
                onPressed: onPressed ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> captureFrame(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(frameKey),
    );
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return bytes!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
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
      const Size(18, 18),
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

  testWidgets('shows the shared running dots and keeps the action', (
    tester,
  ) async {
    await tester.pumpWidget(buildButton(running: true));

    expect(find.byType(RecodexActivityRipple), findsOneWidget);
    expect(find.byIcon(RecodexIcons.arrowDown), findsNothing);
    expect(find.bySemanticsLabel('回到最新内容（任务进行中）'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      'running dots animate with accessibleNavigation=$accessibleNavigation',
      (tester) async {
        await tester.pumpWidget(
          buildButton(
            running: true,
            reduceMotion: false,
            accessibleNavigation: accessibleNavigation,
          ),
        );
        final firstFrame = await captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(await captureFrame(tester), isNot(equals(firstFrame)));

        final nextFrame = await captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 1800));
        expect(await captureFrame(tester), isNot(equals(nextFrame)));
      },
    );
  }

  for (final systemPreference in [false, true]) {
    testWidgets(
      'dots respect reduced motion and resume (system=$systemPreference)',
      (tester) async {
        await tester.pumpWidget(
          buildButton(
            running: true,
            reduceMotion: !systemPreference,
            disableAnimations: systemPreference,
          ),
        );
        final stillFrame = await captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(await captureFrame(tester), equals(stillFrame));

        await tester.pumpWidget(
          buildButton(running: true, reduceMotion: false),
        );
        final resumedFrame = await captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(await captureFrame(tester), isNot(equals(resumedFrame)));

        await tester.pumpWidget(
          buildButton(
            running: true,
            reduceMotion: !systemPreference,
            disableAnimations: systemPreference,
          ),
        );
        final pausedFrame = await captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(await captureFrame(tester), equals(pausedFrame));
      },
    );
  }

  testWidgets('dots animate when the hidden control becomes active', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildButton(running: false, reduceMotion: false, tickerEnabled: false),
    );
    await tester.pumpWidget(buildButton(running: true, reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 250));
    final firstFrame = await captureFrame(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(await captureFrame(tester), isNot(equals(firstFrame)));

    await tester.pumpWidget(buildButton(running: false, reduceMotion: false));
    await tester.pumpAndSettle();
    expect(find.byType(RecodexActivityRipple), findsNothing);
    expect(find.byIcon(RecodexIcons.arrowDown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
