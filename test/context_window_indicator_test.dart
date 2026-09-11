import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/components/context_window_indicator.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  const usage = ContextWindowUsage(usedTokens: 208000, maxTokens: 258400);

  testWidgets('tap reveals context and live updates redraw the ring', (
    tester,
  ) async {
    Widget view(ContextWindowUsage value) => MaterialApp(
      theme: RecodexTheme.dark,
      home: Scaffold(
        body: Center(child: ContextWindowIndicator(usage: value)),
      ),
    );
    await tester.pumpWidget(view(usage));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(208000 / 258400, 0.0001),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(
      find.text('上下文窗口\n80% 已用\n已用 208K / 共 258.4K Token'),
      findsOneWidget,
    );
    await tester.pumpWidget(
      view(const ContextWindowUsage(usedTokens: 40000, maxTokens: 258400)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('15% 已用'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(40000 / 258400, 0.0001),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  for (final running in [false, true]) {
    for (final width in [180.0, 220.0, 320.0, 390.0, 800.0]) {
      testWidgets(
        'composer at $width wide, running=$running, fits context controls',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          Widget view(ContextWindowUsage? value) => MaterialApp(
            theme: RecodexTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ComposerBar(
                    controller: controller,
                    enabled: true,
                    context: ComposerContext.fallback,
                    contextWindowUsage: value,
                    permissionMode: '完全访问权限',
                    running: running,
                    onSend: () {},
                    onStop: () {},
                    onModelChanged: (_) {},
                    onReasoningChanged: (_) {},
                    onPermissionModeChanged: (_) {},
                    onVoicePressed: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(view(usage));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (width >= 320) {
            expect(find.byType(ContextWindowIndicator), findsOneWidget);
          } else {
            expect(find.byType(ContextWindowIndicator), findsNothing);
          }
          expect(find.byTooltip(running ? '停止任务' : '发送消息'), findsOneWidget);
          expect(
            tester.getRect(find.byTooltip(running ? '停止任务' : '发送消息')).right,
            closeTo(tester.getRect(find.byType(ComposerBar)).right - 13, 1),
          );
          await tester.pumpWidget(view(null));
          await tester.pumpAndSettle();
          expect(find.byType(ContextWindowIndicator), findsNothing);
        },
      );
    }
  }

  testWidgets('permission menu uses the desktop labels and three choices', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: ComposerBar(
            controller: controller,
            enabled: true,
            context: ComposerContext.fallback,
            permissionMode: '默认权限',
            running: true,
            onSend: () {},
            onStop: () {},
            onModelChanged: (_) {},
            onReasoningChanged: (_) {},
            onPermissionModeChanged: (_) {},
            onVoicePressed: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('选择权限模式'));
    await tester.pumpAndSettle();
    // The selected label is rendered once on the trigger and once in the menu.
    expect(find.text('请求批准'), findsNWidgets(2));
    expect(find.text('帮我批准'), findsOneWidget);
    expect(find.text('完全访问权限'), findsOneWidget);
    expect(find.text('只读权限'), findsNothing);
  });
}
