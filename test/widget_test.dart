import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/main.dart';

void main() {
  testWidgets('shows device setup first', (tester) async {
    await tester.pumpWidget(const RecodexApp());

    expect(find.text('Recodex'), findsOneWidget);
    expect(find.text('Bridge'), findsWidgets);
    expect(find.text('Connect'), findsOneWidget);
  });
}
