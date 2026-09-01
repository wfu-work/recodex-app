import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/app/components/menu_drawer.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('shows project menu followed by tasks and selects a task', (
    tester,
  ) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    SessionRecord? selected;
    RecodexThemePreference? selectedTheme;
    var projectsRefreshed = false;
    const workspace = WorkspaceInfo(name: 'recodex', path: '/work/recodex');
    const session = SessionRecord(
      id: 'thread-1',
      workspace: '/work/recodex',
      prompt: '修复任务列表',
      status: 'idle',
      createdAt: '2026-08-31T00:00:00Z',
      updatedAt: '2026-08-31T01:00:00Z',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          key: scaffoldKey,
          drawer: RemodexDrawer(
            connected: true,
            pairings: const [],
            activePairing: null,
            workspaces: const [workspace],
            selectedWorkspace: workspace,
            sessions: const [session],
            selectedSessionId: null,
            onSelectPairing: (_) {},
            onSelectWorkspace: (_) {},
            onSelectSession: (value) => selected = value,
            onPairing: () {},
            onNewPairing: () {},
            onSettings: () {},
            themePreference: RecodexThemePreference.system,
            onThemePreferenceChanged: (value) => selectedTheme = value,
            onRefreshProjects: () => projectsRefreshed = true,
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('项目'), findsOneWidget);
    expect(find.text('配对'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('当前主题：跟随系统'), findsOneWidget);
    expect(find.byTooltip('刷新项目'), findsOneWidget);
    expect(find.text('Remodex v1.0.4'), findsNothing);
    expect(find.text('recodex'), findsOneWidget);
    expect(find.text('修复任务列表'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新项目'));
    expect(projectsRefreshed, isTrue);

    await tester.tap(find.byTooltip('当前主题：跟随系统'));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色模式'), findsOneWidget);
    expect(find.text('深色模式'), findsOneWidget);
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(selectedTheme, RecodexThemePreference.dark);

    await tester.tap(find.text('recodex'));
    await tester.pumpAndSettle();
    expect(find.text('修复任务列表'), findsNothing);

    await tester.tap(find.text('recodex'));
    await tester.pumpAndSettle();
    expect(find.text('修复任务列表'), findsOneWidget);

    await tester.tap(find.text('修复任务列表'));
    expect(selected?.id, 'thread-1');
  });
}
