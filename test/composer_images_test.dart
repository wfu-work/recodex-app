// ignore_for_file: must_call_super
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/components/chat_components.dart';
import 'package:recodex/app/components/composer_images.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/main/main_view.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/services/composer_images.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

Future<Uint8List> fixtureImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 600, 320),
    Paint()..color = const Color(0xffe3e9e6),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(50, 60, 500, 200),
      const Radius.circular(16),
    ),
    Paint()..color = const Color(0xff839a8d),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 320);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _Theme extends ThemeController {
  @override
  void onInit() {}
}

class _Bridge extends BridgeController {
  final sent = <String>[];
  bool failUpload = false;
  @override
  void onInit() {}
  @override
  void startLiveTimelineRefresh() {}
  @override
  void stopLiveTimelineRefresh() {}
  @override
  Future<void> removeUploadedImage(
    ComposerImage image,
    ImageMessageContext context,
  ) async {}
  @override
  Future<String> uploadImage(
    ComposerImage image,
    ImageMessageContext context,
    void Function(double) progress,
  ) async {
    if (failUpload) {
      throw const ImageCommandException('CONNECTION_LOST', '网络中断');
    }
    progress(1);
    return image.uploadId(context.key);
  }

  @override
  Future<ImageSendOutcome> sendImageMessage(
    String prompt,
    List<ComposerImage> images,
    List<String> ids,
    ImageMessageContext context, {
    void Function()? onThreadCreated,
  }) async {
    sent.add('${context.threadId}:${images.length}:$prompt');
    return ImageSendOutcome.accepted;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    testWidgets(
      'image tray and mobile menu fit narrow widths with large text (dark=$dark)',
      (tester) async {
        final bytes = (await tester.runAsync(fixtureImage))!;
        final images = List.generate(
          4,
          (i) =>
              ComposerImage(name: '截图-$i.png', bytes: bytes, thumbnail: bytes),
        );
        final input = TextEditingController(text: '请分析这些截图');
        addTearDown(input.dispose);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var removed = 0;
        ComposerImageSource? selected;
        for (final width in [390.0, 280.0, 180.0]) {
          tester.view.physicalSize = Size(width, 950);
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? RecodexTheme.dark : RecodexTheme.light).copyWith(
                platform: TargetPlatform.iOS,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ComposerBar(
                      controller: input,
                      enabled: true,
                      hasAttachments: true,
                      context: ComposerContext.fallback,
                      permissionMode: '默认权限',
                      onSend: () {},
                      imageButton: ComposerImageButton(
                        enabled: true,
                        onSelected: (value) => selected = value,
                      ),
                      imageTray: ComposerImageTray(
                        images: images,
                        onRemove: (_) => removed++,
                      ),
                      onModelChanged: (_) {},
                      onReasoningChanged: (_) {},
                      onPermissionModeChanged: (_) {},
                      onVoicePressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'width=$width');
        }
        await tester.tap(find.byTooltip('移除 截图-0.png'));
        expect(removed, 1);
        await tester.tap(find.byTooltip('添加图片'));
        await tester.pumpAndSettle();
        expect(find.text('相册图片'), findsOneWidget);
        expect(find.text('拍照'), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tap(find.text('拍照'));
        await tester.pumpAndSettle();
        expect(selected, ComposerImageSource.camera);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'normalizes images, builds a thumbnail and rejects unreadable bytes',
    () async {
      final result = await ComposerImage.fromBytes(await fixtureImage());
      final codec = await ui.instantiateImageCodec(result.thumbnail);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 240);
      expect(frame.image.height, 128);
      expect(result.bytes.length, lessThanOrEqualTo(ComposerImage.maxBytes));
      frame.image.dispose();
      codec.dispose();
      await expectLater(
        ComposerImage.fromBytes(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    },
  );

  test('resumes an acknowledged upload after a lost chunk response', () async {
    final bytes = await fixtureImage();
    final image = ComposerImage(
      name: 'test.png',
      bytes: bytes,
      thumbnail: bytes,
    );
    const context = ImageMessageContext(
      host: 'host',
      cwd: '/project',
      threadId: 'a',
    );
    final received = <int>[];
    var loseResponse = true;
    final ids = <String>[];
    Future<Map<String, dynamic>> request(
      String type,
      Map<String, dynamic> command,
    ) async {
      switch (type) {
        case 'image.upload.begin':
          ids.add(command['uploadId']);
          return {'offset': received.length};
        case 'image.upload.append':
          expect(command['offset'], received.length);
          received.addAll(base64Decode(command['data']));
          if (loseResponse) {
            loseResponse = false;
            throw const ImageCommandException(
              'CONNECTION_LOST',
              'lost receipt',
            );
          }
          return {'offset': received.length};
        default:
          expect(received, orderedEquals(bytes));
          return {'attachmentId': command['uploadId']};
      }
    }

    Future<String> upload() => uploadComposerImage(
      image: image,
      context: context,
      request: request,
      onProgress: (_) {},
      chunkBytes: 128,
    );
    await expectLater(upload(), throwsA(isA<ImageCommandException>()));
    expect(await upload(), ids.first);
    expect(ids.toSet(), hasLength(1));
    expect(
      image.uploadId(
        const ImageMessageContext(
          host: 'other',
          cwd: '/project',
          threadId: 'a',
        ).key,
      ),
      isNot(ids.first),
    );
  });

  testWidgets(
    'image-only drafts send with Enter, busy uploads cannot send twice',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sent = 0;
      var busy = false;
      var pastes = 0;
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          theme: RecodexTheme.light,
          home: Scaffold(
            body: ComposerBar(
              controller: controller,
              enabled: true,
              hasAttachments: true,
              busy: busy,
              context: ComposerContext.fallback,
              permissionMode: '默认权限',
              onSend: () => sent++,
              onPaste: () => pastes++,
              onModelChanged: (_) {},
              onReasoningChanged: (_) {},
              onPermissionModeChanged: (_) {},
              onVoicePressed: () {},
            ),
          ),
        ),
      );
      await mount();
      await tester.tap(find.byType(TextField));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(pastes, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
      busy = true;
      await mount();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    },
  );

  testWidgets(
    'main keeps image drafts per task, retains upload failures, and clears accepted sends',
    (tester) async {
      final bytes = await tester.runAsync(fixtureImage);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async => call.method == 'image' ? bytes : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('pasteboard'),
          null,
        ),
      );
      Get.testMode = true;
      addTearDown(Get.reset);
      final bridge = Get.put<BridgeController>(_Bridge()) as _Bridge;
      Get.put<ThemeController>(_Theme());
      bridge.connected.value = true;
      bridge.imageAttachmentsAvailable.value = true;
      bridge.selectedWorkspace.value = const WorkspaceInfo(
        name: 'p',
        path: '/project',
      );
      bridge.selectedSessionId.value = 'a';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: RecodexTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const MainPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byTooltip('添加图片'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('粘贴图片'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ComposerImageTray),
        findsOneWidget,
        reason:
            '${bridge.lastError.value}; enabled=${tester.widget<ComposerImageButton>(find.byType(ComposerImageButton)).enabled}',
      );
      bridge.selectedSessionId.value = 'b';
      await tester.pumpAndSettle();
      expect(find.byType(ComposerImageTray), findsNothing);
      bridge.selectedSessionId.value = 'a';
      await tester.pumpAndSettle();
      expect(find.byType(ComposerImageTray), findsOneWidget);
      for (final width in [390.0, 280.0, 220.0, 180.0, 900.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width=$width');
        expect(find.byTooltip('添加图片'), findsOneWidget);
      }
      bridge.failUpload = true;
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerImageTray), findsOneWidget);
      expect(bridge.sent, isEmpty);
      expect(find.textContaining('上传未完成'), findsOneWidget);
      bridge.failUpload = false;
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pumpAndSettle();
      expect(bridge.sent, ['a:1:']);
      expect(find.byType(ComposerImageTray), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
