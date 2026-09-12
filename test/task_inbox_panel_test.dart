import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/widget/task_inbox_panel.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('groups pinned tasks before recent tasks and ignores archives', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = now.toIso8601String();
    final yesterday = now.subtract(const Duration(days: 1)).toIso8601String();
    const pinned = SessionRecord(
      id: 'pinned',
      workspace: '/workspace',
      prompt: '置顶任务',
      status: 'idle',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      isPinned: true,
    );
    final sessions = [
      pinned.copyWith(recencyAt: today),
      SessionRecord(
        id: 'recent',
        workspace: '/workspace',
        prompt: '最近任务',
        status: 'idle',
        createdAt: yesterday,
        updatedAt: yesterday,
        recencyAt: today,
      ),
      SessionRecord(
        id: 'old',
        workspace: '/workspace',
        prompt: '昨天任务',
        status: 'idle',
        createdAt: yesterday,
        updatedAt: yesterday,
        recencyAt: yesterday,
      ),
      const SessionRecord(
        id: 'archived',
        workspace: '/workspace',
        prompt: '归档任务',
        status: 'archived',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        isArchived: true,
      ),
    ];
    SessionRecord? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: Scaffold(
          body: TaskInboxPanel(
            sessions: sessions,
            selectedSessionId: null,
            onSelect: (session) => selected = session,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('优先级'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('归档任务'), findsNothing);
    expect(
      tester.getTopLeft(find.text('置顶任务')).dy,
      lessThan(tester.getTopLeft(find.text('最近任务')).dy),
    );
    await tester.tap(find.text('最近任务'));
    expect(selected?.id, 'recent');
  });

  testWidgets('shows an empty state when there are no active tasks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: Scaffold(
          body: TaskInboxPanel(
            sessions: const [],
            selectedSessionId: null,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('暂无任务'), findsOneWidget);
    expect(find.text('新建对话后，任务会显示在这里'), findsOneWidget);
  });
}
