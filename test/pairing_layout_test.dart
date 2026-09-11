// ignore_for_file: must_call_super

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/pairing/pairing_view.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

const _profile = PairingProfile(
  id: 'macair',
  name: 'macair',
  baseUrl: 'wss://relay.example.com/v1/connect',
  spaceId: 'space-macair-codex',
  deviceName: 'phone',
  deviceId: 'phone-main',
  targetDeviceId: 'macair-codex',
  endpointType: 'app',
  deviceKey: 'preview-key',
  endpointPublicKey: 'public-key-for-layout-preview-only',
  pairingToken: 'preview-token',
  endpointGrant: 'preview-grant',
  tokenExpiresAt: 0,
  grantExpiresAt: 0,
);

class _Bridge extends BridgeController {
  final selected = <String>[];
  final deleted = <String>[];
  final saved = <PairingProfile>[];
  @override
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<EndpointKeyMaterial> prepareEndpointKey({String? deviceKey}) async =>
      const EndpointKeyMaterial(
        deviceKey: 'preview-key',
        publicKey: 'public-key-for-layout-preview-only',
      );
  @override
  Future<void> switchPairing(String id, {bool autoConnect = true}) async {
    selected.add(id);
    activePairingId.value = id;
  }

  @override
  Future<void> deletePairing(String id) async {
    deleted.add(id);
    pairings.removeWhere((profile) => profile.id == id);
  }

  @override
  Future<void> upsertPairing(
    PairingProfile profile, {
    bool connect = true,
  }) async {
    saved.add(profile);
  }
}

Future<_Bridge> _mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool dark = false,
}) async {
  Get.testMode = true;
  addTearDown(Get.reset);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final bridge = _Bridge();
  Get.put<BridgeController>(bridge);
  bridge.pairings.assignAll([_profile]);
  bridge.activePairingId.value = _profile.id;
  bridge.connected.value = true;
  bridge.composerContext.value = ComposerContext.fallback.copyWith(
    bridgeVersion: 'relay-protocol-v1',
    codexVersion: 'codex-relay-plugin/0.153.4+desktop.20260911',
    model: 'gpt-6-astra',
  );
  await tester.pumpWidget(
    GetMaterialApp(
      theme: dark ? RecodexTheme.dark : RecodexTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const PairingPage(),
    ),
  );
  await tester.pumpAndSettle();
  return bridge;
}

void main() {
  for (final dark in [false, true]) {
    for (final size in [
      (320.0, 1.0),
      (390.0, 1.0),
      (390.0, 2.0),
      (1000.0, 1.0),
    ]) {
      final (width, scale) = size;
      testWidgets('pairing layout fits width=$width scale=$scale dark=$dark', (
        tester,
      ) async {
        await _mount(tester, width: width, scale: scale, dark: dark);
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          expect(
            tester.getSize(find.widgetWithText(FilledButton, '新建配对')).height,
            44,
          );
        }
        await tester.tap(find.text('macair'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('保存并连接'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final testButton = find.widgetWithText(OutlinedButton, '测试连接');
        final saveButton = find.widgetWithText(FilledButton, '保存并连接');
        if (scale == 1) {
          expect(tester.getSize(testButton).height, 44);
          expect(tester.getSize(saveButton).height, 44);
        }
        final testRect = tester.getRect(testButton);
        final saveRect = tester.getRect(saveButton);
        expect(testRect.overlaps(saveRect), isFalse);
        expect(testRect.left, greaterThanOrEqualTo(0));
        expect(saveRect.right, lessThanOrEqualTo(width));
        await tester.ensureVisible(find.text('用量读取'));
        await tester.pumpAndSettle();
        final version = tester.widget<SelectableText>(
          find.widgetWithText(
            SelectableText,
            'codex-relay-plugin/0.153.4+desktop.20260911',
          ),
        );
        expect(version.maxLines, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'compact menu preserves default, edit, save, and confirmed delete',
    (tester) async {
      final bridge = await _mount(tester);
      bridge.activePairingId.value = 'another-host';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设为默认配对'));
      await tester.pumpAndSettle();
      expect(bridge.selected, ['macair']);
      expect(find.text('默认配对'), findsOneWidget);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑配对'));
      await tester.pumpAndSettle();
      expect(find.text('编辑配对'), findsOneWidget);
      expect(find.text('远程 Codex'), findsOneWidget);
      await tester.ensureVisible(find.text('保存并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(bridge.saved.single.name, _profile.name);
      expect(bridge.saved.single.pairingToken, _profile.pairingToken);
      expect(bridge.saved.single.endpointGrant, _profile.endpointGrant);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除配对'));
      await tester.pumpAndSettle();
      expect(bridge.deleted, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(bridge.deleted, isEmpty);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除配对'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(bridge.deleted, ['macair']);
      expect(find.text('还没有配对'), findsOneWidget);
    },
  );
}
