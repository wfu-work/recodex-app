import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/recodex_notice.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  late BuildContext pageContext;
  var taps = 0;

  Future<void> mount(
    WidgetTester tester, {
    bool accessibleNavigation = false,
    bool reduceMotion = false,
    bool dark = true,
    double textScale = 1,
  }) async {
    taps = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: (dark ? RecodexTheme.dark : RecodexTheme.light).copyWith(
          platform: TargetPlatform.android,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 44),
            viewPadding: const EdgeInsets.only(top: 44),
            viewInsets: const EdgeInsets.only(bottom: 300),
            accessibleNavigation: accessibleNavigation,
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: RecodexNoticeHost(child: child!),
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('页面操作'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets('notice sits below status bar and leaves page actions usable', (
    tester,
  ) async {
    await mount(tester);
    RecodexNotice.show(
      pageContext,
      '连接测试成功，Relay 连接正常。',
      tone: RecodexNoticeTone.success,
    );
    await tester.pumpAndSettle();
    final card = find
        .ancestor(
          of: find.text('连接测试成功，Relay 连接正常。'),
          matching: find.byType(Material),
        )
        .first;
    final bounds = tester.getRect(card);
    expect(bounds.top, 56);
    expect(bounds.left, 16);
    expect(bounds.right, 374);
    expect(find.byIcon(RecodexIcons.checkCircle), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('页面操作'));
    expect(taps, 1);
    await tester.tap(find.bySemanticsLabel('关闭提示'));
    await tester.pumpAndSettle();
    expect(find.text('连接测试成功，Relay 连接正常。'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new notice replaces the old one and restarts its timer', (
    tester,
  ) async {
    await mount(tester);
    RecodexNotice.show(
      pageContext,
      '旧提示',
      duration: const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    RecodexNotice.show(pageContext, '新提示');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('旧提示'), findsNothing);
    expect(find.text('新提示'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('新提示'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('long accessible notice remains readable (dark=$dark)', (
      tester,
    ) async {
      await mount(
        tester,
        dark: dark,
        accessibleNavigation: true,
        reduceMotion: true,
        textScale: 2,
      );
      final message = List.filled(12, '连接失败，请检查 Relay 地址和网络后重试。').join();
      RecodexNotice.show(pageContext, message, tone: RecodexNoticeTone.error);
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      expect(tester.takeException(), isNull);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(message),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
    });
  }

  testWidgets(
    'notice survives dialog dismissal and cancels timers on disposal',
    (tester) async {
      await mount(tester);
      late BuildContext dialogContext;
      final dialog = showDialog<void>(
        context: pageContext,
        builder: (context) {
          dialogContext = context;
          return const AlertDialog(title: Text('操作结果'));
        },
      );
      await tester.pumpAndSettle();
      RecodexNotice.show(dialogContext, '已复制', tone: RecodexNoticeTone.success);
      Navigator.of(dialogContext).pop();
      await tester.pumpAndSettle();
      await dialog;
      expect(find.text('已复制'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
