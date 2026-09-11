// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/main/main_view.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/routes/app_pages.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

class _Bridge extends BridgeController {
  final sentPrompts = <String>[];

  @override
  void onInit() {}
  @override
  void startLiveTimelineRefresh() {}
  @override
  void stopLiveTimelineRefresh() {}
  @override
  void startSession(String prompt) => sentPrompts.add(prompt);
}

class _Theme extends ThemeController {
  @override
  void onInit() {}
}

void main() {
  Future<void> pumpComposer(
    WidgetTester tester, {
    required TextEditingController controller,
    required VoidCallback onSend,
    bool enabled = true,
    bool running = false,
    VoidCallback? onSteer,
    VoidCallback? onStop,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: RecodexTheme.light,
      home: Scaffold(
        body: ComposerBar(
          controller: controller,
          enabled: enabled,
          running: running,
          context: ComposerContext.fallback,
          permissionMode: '默认权限',
          onSend: onSend,
          onSteer: onSteer,
          onStop: onStop,
          onModelChanged: (_) {},
          onReasoningChanged: (_) {},
          onPermissionModeChanged: (_) {},
          onVoicePressed: () {},
        ),
      ),
    ),
  );

  testWidgets('Enter sends once; Shift+Enter inserts a newline at selection', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final sent = <String>[];
    await pumpComposer(
      tester,
      controller: controller,
      onSend: () {
        sent.add(controller.text);
      },
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '第一行待替换末尾');
    controller.selection = const TextSelection(baseOffset: 3, extentOffset: 6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.text, '第一行\n末尾');
    expect(controller.selection.baseOffset, 4);
    expect(sent, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(sent, ['第一行\n末尾']);
    expect(controller.text, '第一行\n末尾');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(sent, ['第一行\n末尾', '第一行\n末尾']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter leaves Chinese composing text to the IME', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sent = 0;
    await pumpComposer(tester, controller: controller, onSend: () => sent++);
    await tester.tap(find.byType(TextField));
    const composing = TextEditingValue(
      text: 'nihao',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    // Unhandled by Flutter so the platform IME can confirm its candidate.
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.enter), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(sent, 0);
    expect(controller.value, composing);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, 1);
  });

  testWidgets('empty, disabled, and running drafts cannot be sent with Enter', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sent = 0;
    var steered = 0;
    var stopped = 0;
    for (final running in [false, true]) {
      await pumpComposer(
        tester,
        controller: controller,
        onSend: () => sent++,
        running: running,
        onSteer: () => steered++,
        onStop: () => stopped++,
      );
      await tester.enterText(find.byType(TextField), running ? '保留草稿' : '  ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sent, 0);
      expect(steered, 0);
      expect(stopped, 0);
      expect(controller.text, running ? '保留草稿' : '  ');
    }
    await pumpComposer(
      tester,
      controller: controller,
      onSend: () => sent++,
      enabled: false,
    );
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, 0);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'mobile keyboard opens only on tap and send submits to MainPage',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final bridge = _Bridge();
      Get.put<BridgeController>(bridge);
      Get.put<ThemeController>(_Theme());
      await tester.pumpWidget(
        GetMaterialApp(
          theme: RecodexTheme.light,
          home: const MainPage(),
          getPages: [
            GetPage(
              name: Routes.settings,
              page: () => const Scaffold(body: Text('测试设置页')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byType(ComposerBar),
        matching: find.byType(TextField),
      );
      FocusNode inputFocus() => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byType(ComposerBar),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(inputFocus().hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // Restoring a connection and task must not summon the keyboard.
      bridge.connected.value = true;
      bridge.selectedWorkspace.value = const WorkspaceInfo(
        name: 'project',
        path: '/tmp/project',
      );
      bridge.selectedSessionId.value = 'restored';
      await tester.pumpAndSettle();
      expect(inputFocus().hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(input);
      await tester.pumpAndSettle();
      expect(inputFocus().hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.send',
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  手机发送的问题  ',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(bridge.sentPrompts, ['手机发送的问题']);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(inputFocus().hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(input);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('测试设置页'), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(inputFocus().hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // New-task shortcuts also leave the composer waiting for an explicit tap.
      await tester.tap(input);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(bridge.selectedSessionId.value, isNull);
      expect(inputFocus().hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
