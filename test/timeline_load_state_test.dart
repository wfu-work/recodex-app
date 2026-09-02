import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/liquid_glass.dart';
import 'package:recodex/app/pages/main/widget/timeline_load_state.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  Widget buildState({
    required bool loading,
    int elapsedSeconds = 0,
    String error = '',
    VoidCallback? onRetry,
  }) {
    return MaterialApp(
      theme: RecodexTheme.light,
      home: Scaffold(
        body: TimelineLoadState(
          loading: loading,
          elapsedSeconds: elapsedSeconds,
          error: error,
          onRetry: onRetry ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows measurable progress while loading', (tester) async {
    await tester.pumpWidget(buildState(loading: true, elapsedSeconds: 12));

    expect(find.text('正在加载任务对话'), findsOneWidget);
    expect(find.text('已等待 12 秒 · 首次加载通常需要几秒'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('重新加载'), findsNothing);
  });

  testWidgets('centers the first-load card in the available width', (
    tester,
  ) async {
    await tester.pumpWidget(buildState(loading: true));

    final card = tester.getRect(find.byType(LiquidGlass));
    expect(card.center.dx, closeTo(400, 1));
  });

  testWidgets('shows the failure reason and retry action', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      buildState(
        loading: false,
        error: 'Relay 请求超时，请检查网络连接。',
        onRetry: () => retryCount++,
      ),
    );

    expect(find.text('任务对话加载失败'), findsOneWidget);
    expect(find.text('Relay 请求超时，请检查网络连接。'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);

    await tester.tap(find.text('重新加载'));
    expect(retryCount, 1);
  });

  testWidgets('explains an empty task response', (tester) async {
    await tester.pumpWidget(buildState(loading: false));

    expect(find.text('任务暂无可展示内容'), findsOneWidget);
    expect(find.text('目标主机返回了空的任务记录，可以重新加载试试。'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.byIcon(RecodexIcons.info), findsOneWidget);
  });
}
