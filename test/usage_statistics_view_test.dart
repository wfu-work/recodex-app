// ignore_for_file: must_call_super

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/usage_heatmap.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/settings/settings_preferences_controller.dart';
import 'package:recodex/app/pages/settings/settings_view.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/pages/settings/usage_statistics_view.dart';
import 'package:recodex/app/routes/app_pages.dart';
import 'package:recodex/app/services/task_notification_controller.dart';
import 'package:recodex/app/services/usage_statistics.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _Bridge extends BridgeController {
  List<AnswerUsageRecord> records = [];
  Future<List<AnswerUsageRecord>> Function()? loader;
  @override
  void onInit() {}
  @override
  Future<List<AnswerUsageRecord>> loadUsageStatistics() async =>
      loader == null ? records : loader!();
}

class _Theme extends ThemeController {
  @override
  void onInit() {}
}

class _Preferences extends SettingsPreferencesController {
  @override
  void onInit() {}
}

AnswerUsageRecord record(String title, DateTime? date, int tokens) =>
    AnswerUsageRecord(
      threadId: title,
      turnId: 'turn',
      title: title,
      workspace: '/workspace/recodex',
      completedAt: date,
      usage: TokenUsage(
        inputTokens: tokens - 10,
        outputTokens: 10,
        totalTokens: tokens,
        cachedInputTokens: 40,
        scope: TokenUsageScope.turn,
      ),
      durationMs: 51000,
    );

void main() {
  late _Bridge bridge;
  setUp(() {
    Get.testMode = true;
    bridge = _Bridge();
    Get.put<BridgeController>(bridge);
  });
  tearDown(Get.reset);

  Widget page({bool dark = false, double scale = 1}) => GetMaterialApp(
    theme: dark ? RecodexTheme.dark : RecodexTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: UsageStatisticsPage(now: DateTime(2026, 9, 11)),
    ),
  );

  testWidgets('settings entry navigates to the usage page', (tester) async {
    Get.put<ThemeController>(_Theme());
    Get.put<SettingsPreferencesController>(_Preferences());
    Get.put(TaskNotificationController());
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        getPages: AppPages.routes,
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('消耗统计'), 300);
    await tester.ensureVisible(find.text('消耗统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('消耗统计'));
    await tester.pumpAndSettle();
    expect(find.byType(UsageStatisticsPage), findsOneWidget);
    expect(find.byType(UsageHeatmap), findsOneWidget);
  });

  testWidgets('selecting a day filters details and clearing it restores them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bridge.records = [
      record('今天的回答', DateTime(2026, 9, 11), 1200),
      record('昨天的回答', DateTime(2026, 9, 10), 2300),
    ];
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('3.5K'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usage-day-2026/09/10')));
    await tester.pumpAndSettle();
    expect(find.text('2026/09/10 的明细'), findsOneWidget);
    expect(find.text('昨天的回答'), findsOneWidget);
    expect(find.text('今天的回答'), findsNothing);
    await tester.tap(find.text('清除日期'));
    await tester.pumpAndSettle();
    expect(find.text('今天的回答'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '昨天');
    await tester.pumpAndSettle();
    expect(find.text('2.3K'), findsOneWidget);
    expect(find.text('今天的回答'), findsNothing);
  });

  testWidgets(
    'range filters and all-time totals treat undated records honestly',
    (tester) async {
      bridge.records = [
        record('最近', DateTime(2026, 9, 11), 100),
        record('更早', DateTime(2026, 8, 1), 200),
        record('没有日期', null, 400),
      ];
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('300'), findsOneWidget);
      await tester.tap(find.text('近 7 天'));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('700'), findsOneWidget);
      final chart = tester.widget<UsageHeatmap>(find.byType(UsageHeatmap));
      expect(
        chart.days.values.fold(0, (int sum, day) => sum + day.totalTokens),
        300,
      );
    },
  );

  testWidgets('late reads from a previous host cannot repopulate the page', (
    tester,
  ) async {
    final first = Completer<List<AnswerUsageRecord>>();
    bridge.loader = () => first.future;
    await tester.pumpWidget(page());
    await tester.pump();
    bridge.loader = () async => [record('新主机', DateTime(2026, 9, 11), 200)];
    bridge.targetDeviceId.value = 'new-host';
    await tester.pumpAndSettle();
    first.complete([record('旧主机', DateTime(2026, 9, 11), 9000)]);
    await tester.pumpAndSettle();
    expect(find.text('200'), findsOneWidget);
    expect(find.text('9K'), findsNothing);
  });

  testWidgets('failed reads have a retry and preserve loaded statistics', (
    tester,
  ) async {
    bridge.records = [record('回答', DateTime(2026, 9, 11), 300)];
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    bridge.loader = () => Future.error(StateError('storage unavailable'));
    await tester.tap(find.text('刷新统计'));
    await tester.pumpAndSettle();
    expect(find.text('消耗记录读取失败，请重试。'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    bridge.loader = () async => [];
    await tester.tap(find.text('刷新统计'));
    await tester.pumpAndSettle();
    expect(find.text('消耗记录读取失败，请重试。'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'narrow ${dark ? 'dark' : 'light'} page supports large text and empty days',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bridge.records = [record('长标题' * 30, DateTime(2026, 9, 11), 123456789)];
        await tester.pumpWidget(page(dark: dark, scale: 1.4));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('usage-day-2026/09/11')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('usage-day-2026/09/11')));
        await tester.pumpAndSettle();
        expect(find.text('2026/09/11 的明细'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('长标题' * 30),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
