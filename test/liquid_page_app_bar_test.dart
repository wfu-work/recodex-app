import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/liquid_page_app_bar.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('keeps the macOS back button clear of traffic lights', (
    tester,
  ) async {
    final macTheme = RecodexTheme.light.copyWith(
      platform: TargetPlatform.macOS,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: macTheme,
        home: Scaffold(
          appBar: const LiquidPageAppBar(title: '设置'),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backButton = find.byType(IconButton);
    expect(tester.getSize(backButton), const Size(56, 56));
    expect(tester.getTopLeft(backButton).dx, 56);
  });
}
