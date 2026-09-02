import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/pages/main/widget/home_header.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('shows the workbench actions as an icon-only control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: Scaffold(
          body: HomeHeader(
            title: 'recodex',
            subtitle: '',
            backgroundProgress: 0,
            topPadding: 0,
            onRefreshGit: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(RecodexIcons.more), findsOneWidget);
    expect(find.text('操作'), findsNothing);
  });

  testWidgets('shows the task name above the project name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: Scaffold(
          body: HomeHeader(
            title: '调整侧边栏主题切换样式',
            subtitle: 'codex-relay-plugin',
            backgroundProgress: 0,
            topPadding: 0,
            onRefreshGit: () {},
          ),
        ),
      ),
    );

    expect(find.text('调整侧边栏主题切换样式'), findsOneWidget);
    expect(find.text('codex-relay-plugin'), findsOneWidget);
    final title = tester.widget<Text>(find.text('调整侧边栏主题切换样式'));
    expect(title.style?.fontSize, 24);
    expect(title.style?.fontWeight, FontWeight.w600);
  });
}
