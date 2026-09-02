import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/pages/main/widget/task_output_dialog.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('binds the output scrollbar to its scroll view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: const Scaffold(body: TaskOutputDialog(output: '任务输出')),
      ),
    );
    await tester.pump();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
