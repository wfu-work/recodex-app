// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _Theme extends ThemeController {
  @override
  void onInit() {}
}

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('file references fit resized answers, dark=$dark scale=$scale', (
        tester,
      ) async {
        Get.testMode = true;
        Get.put<ThemeController>(_Theme());
        addTearDown(Get.reset);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final width = ValueNotifier(900.0);
        addTearDown(width.dispose);
        const filename = 'admin-pool-account-create.component.html';
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? RecodexTheme.dark : RecodexTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (context, value, child) => SizedBox(
                    key: const ValueKey('answer-width'),
                    width: value,
                    child: child,
                  ),
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: const SingleChildScrollView(
                      child: AssistantAnswerBlock(
                        completed: true,
                        showReasoning: false,
                        showUsageMetrics: false,
                        events: [
                          SessionEvent(
                            kind: 'assistant',
                            text:
                                '- [$filename](/project/src/$filename:42)\n'
                                '  - [admin-pool-account-create.component.scss]'
                                '(/project/src/admin-pool-account-create.component.scss)\n'
                                '    - [admin-pool-account-create.component.ts]'
                                '(file:///project/src/admin-pool-account-create.component.ts)\n'
                                '参见 [windows.dart](C:\\project\\windows.dart:10)。\n'
                                '另见 [a.dart](/project/a.dart) 继续阅读。\n'
                                '已通过 ESLint、Prettier 和 Angular development 构建。',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final next in [
          900.0,
          400.0,
          360.0,
          328.0,
          280.0,
          220.0,
          180.0,
          900.0,
        ]) {
          width.value = next;
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'answer width $next');
          final bounds = tester.getRect(
            find.byKey(const ValueKey('answer-width')),
          );
          for (final name in [
            filename,
            'admin-pool-account-create.component.scss',
            'admin-pool-account-create.component.ts',
            'windows.dart',
            'a.dart',
          ]) {
            final link = find.text(name);
            expect(link, findsOneWidget);
            expect(
              tester.getRect(link).right,
              lessThanOrEqualTo(bounds.right + 0.01),
            );
          }
        }
        // Short references still take only their own width in running prose.
        expect(
          tester.getSize(find.text('a.dart')).width,
          lessThan(150 * scale),
        );
      });
    }
  }
}
