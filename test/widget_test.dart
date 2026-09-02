import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/main.dart';

void main() {
  testWidgets('shows remodex home first', (tester) async {
    await tester.pumpWidget(const RecodexApp());
    await tester.pumpAndSettle();

    expect(find.text('新对话', skipOffstage: false), findsOneWidget);
    expect(find.text('等待 Relay 连接', skipOffstage: false), findsOneWidget);
    expect(
      find.text(
        'Ask anything... @files, \$skills, /commands',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });
}
