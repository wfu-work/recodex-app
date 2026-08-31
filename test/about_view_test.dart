import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/pages/about/about_view.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('shows the compact brand and product information layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: RecodexTheme.light, home: const AboutPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('Recodex'), findsOneWidget);
    expect(find.text('Companion'), findsOneWidget);
    expect(find.text('产品定位'), findsOneWidget);
    expect(find.text('应用信息'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('连接与安全', skipOffstage: false), findsOneWidget);
    expect(find.text('Relay Protocol v1', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Ed25519 Endpoint proof', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Recodex Companion 图标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the about layout usable in a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(theme: RecodexTheme.light, home: const AboutPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recodex'), findsOneWidget);
    expect(
      find.text('Ed25519 Endpoint proof', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
