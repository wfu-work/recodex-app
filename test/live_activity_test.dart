import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/live_activity.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

const _frameKey = ValueKey('shimmer-frame');

Widget _buildLabel({
  bool accessibleNavigation = false,
  bool disableAnimations = false,
  bool reduceMotion = false,
  bool tickerEnabled = true,
}) => MaterialApp(
  theme: RecodexTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      accessibleNavigation: accessibleNavigation,
      disableAnimations: disableAnimations,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: TickerMode(
        enabled: tickerEnabled,
        child: RepaintBoundary(
          key: _frameKey,
          child: SizedBox(
            width: 320,
            child: RecodexActivityShimmerText(
              text: '正在生成回答...',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              reduceMotion: reduceMotion,
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _captureFrame(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frameKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      'live text visibly sweeps with accessibleNavigation=$accessibleNavigation',
      (tester) async {
        await tester.pumpWidget(
          _buildLabel(accessibleNavigation: accessibleNavigation),
        );
        final firstFrame = await _captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 450));
        final highlightedFrame = await _captureFrame(tester);
        expect(highlightedFrame, isNot(equals(firstFrame)));
        await tester.pump(const Duration(milliseconds: 1600));
        expect(await _captureFrame(tester), equals(highlightedFrame));
        expect(find.bySemanticsLabel('正在生成回答...'), findsOneWidget);
      },
    );
  }

  for (final systemPreference in [false, true]) {
    testWidgets(
      'live text respects reduced motion and resumes (system=$systemPreference)',
      (tester) async {
        await tester.pumpWidget(
          _buildLabel(
            accessibleNavigation: true,
            disableAnimations: systemPreference,
            reduceMotion: !systemPreference,
          ),
        );
        final stillFrame = await _captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 450));
        expect(await _captureFrame(tester), equals(stillFrame));
        expect(find.byType(ShaderMask), findsNothing);

        await tester.pumpWidget(_buildLabel(accessibleNavigation: true));
        final resumedFrame = await _captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 450));
        expect(await _captureFrame(tester), isNot(equals(resumedFrame)));

        await tester.pumpWidget(
          _buildLabel(
            accessibleNavigation: true,
            disableAnimations: systemPreference,
            reduceMotion: !systemPreference,
          ),
        );
        final pausedFrame = await _captureFrame(tester);
        await tester.pump(const Duration(milliseconds: 450));
        expect(await _captureFrame(tester), equals(pausedFrame));
      },
    );
  }

  testWidgets('live text animates after its route becomes active', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildLabel(accessibleNavigation: true, tickerEnabled: false),
    );
    await tester.pumpWidget(_buildLabel(accessibleNavigation: true));
    final firstFrame = await _captureFrame(tester);
    await tester.pump(const Duration(milliseconds: 450));
    expect(await _captureFrame(tester), isNot(equals(firstFrame)));
    expect(tester.takeException(), isNull);
  });
}
