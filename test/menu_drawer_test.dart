import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/app/components/menu_drawer.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('shows a rotating indicator before running task titles', (
    tester,
  ) async {
    SessionRecord? selected;
    const workspace = WorkspaceInfo(name: 'recodex', path: '/work/recodex');
    const runningSession = SessionRecord(
      id: 'thread-running',
      workspace: '/work/recodex',
      prompt: '正在运行的任务',
      status: 'running',
      createdAt: '2026-08-31T00:00:00Z',
      updatedAt: '2026-08-31T01:00:00Z',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: RemodexDrawer(
          connected: true,
          pairings: const [],
          activePairing: null,
          workspaces: const [workspace],
          selectedWorkspace: workspace,
          sessions: const [runningSession],
          selectedSessionId: null,
          onSelectPairing: (_) {},
          onSelectWorkspace: (_) {},
          onSelectSession: (value) => selected = value,
          onPairing: () {},
          onNewPairing: () {},
          onSettings: () {},
          themePreference: RecodexThemePreference.system,
          onThemePreferenceChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('正在运行的任务'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('正在运行的任务'));
    expect(selected?.id, 'thread-running');
  });

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
    const pinnedSession = SessionRecord(
      id: 'thread-pinned',
      workspace: '/work/recodex',
      prompt: '置顶任务',
      status: 'done',
      createdAt: '2026-08-31T00:00:00Z',
      updatedAt: '2026-08-31T02:00:00Z',
      isPinned: true,
    );
    const archivedSession = SessionRecord(
      id: 'thread-archived',
      workspace: '/work/recodex',
      prompt: '归档任务',
      status: 'done',
      createdAt: '2026-08-31T00:00:00Z',
      updatedAt: '2026-08-31T03:00:00Z',
      isArchived: true,
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
            sessions: const [pinnedSession, session, archivedSession],
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
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('归档'), findsOneWidget);
    expect(find.text('置顶任务'), findsOneWidget);
    expect(find.text('归档任务'), findsOneWidget);
    expect(find.text('配对'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('当前主题：跟随系统'), findsOneWidget);
    expect(find.byTooltip('刷新项目'), findsOneWidget);
    expect(find.text('Remodex v1.0.4'), findsNothing);
    expect(find.text('recodex'), findsOneWidget);
    expect(find.text('修复任务列表'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新项目'));
    expect(projectsRefreshed, isTrue);

    expect(find.byTooltip('当前主题：跟随系统'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-light')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-dark')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
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

  testWidgets('shows project refresh progress while the catalog is loading', (
    tester,
  ) async {
    var refreshed = false;
    const workspace = WorkspaceInfo(name: 'recodex', path: '/work/recodex');

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: RemodexDrawer(
          connected: true,
          pairings: const [],
          activePairing: null,
          workspaces: const [workspace],
          selectedWorkspace: workspace,
          sessions: const [],
          selectedSessionId: null,
          onSelectPairing: (_) {},
          onSelectWorkspace: (_) {},
          onSelectSession: (_) {},
          onPairing: () {},
          onNewPairing: () {},
          onSettings: () {},
          themePreference: RecodexThemePreference.system,
          onThemePreferenceChanged: (_) {},
          onRefreshProjects: () => refreshed = true,
          refreshing: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('正在刷新项目'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('正在刷新项目'));
    expect(refreshed, isFalse);
  });
}
