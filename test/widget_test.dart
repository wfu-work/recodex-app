import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/main.dart';

void main() {
  testWidgets('shows remodex home first', (tester) async {
    await tester.pumpWidget(const RecodexApp());

    expect(find.text('Remodex'), findsOneWidget);
    expect(find.text('未选择工作区'), findsOneWidget);
    expect(find.text('输入任务...'), findsOneWidget);
  });
}
