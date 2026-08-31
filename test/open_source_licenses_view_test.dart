import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/pages/about/open_source_licenses_view.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('shows the open-source license overview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: const OpenSourceLicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开源许可'), findsNWidgets(2));
    expect(find.text('本应用'), findsOneWidget);
    expect(find.text('第三方组件'), findsOneWidget);
    expect(find.text('Recodex Companion'), findsOneWidget);
    expect(find.text('MIT License'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps license rows usable in a narrow window', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: const OpenSourceLicensesPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recodex Companion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
