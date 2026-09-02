import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/pairing/pairing_view.dart';
import 'package:recodex/app/routes/app_pages.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(BridgeController(), permanent: true);
  });

  tearDown(Get.reset);

  testWidgets('generates and displays an endpoint public key before saving', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        getPages: AppPages.routes,
        initialRoute: Routes.pairing,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('新建配对'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('连接认证'), findsOneWidget);
    expect(find.text('Relay 连接地址'), findsOneWidget);
    expect(find.text('空间 ID'), findsOneWidget);
    expect(find.text('目标主机接入端 ID'), findsOneWidget);
    expect(find.text('本机接入端 ID'), findsOneWidget);
    expect(find.text('连接令牌'), findsOneWidget);
    expect(find.text('接入端授权凭证'), findsOneWidget);
    expect(find.text('Ed25519 公钥'), findsOneWidget);
    expect(find.byTooltip('复制公钥'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('保存并连接'), findsOneWidget);

    final publicKeyField = tester.widget<TextField>(
      find.byType(TextField).at(5),
    );
    expect(publicKeyField.controller?.text, hasLength(43));
  });

  testWidgets('opens pairing details when tapping the card body', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        getPages: AppPages.routes,
        initialRoute: Routes.pairing,
      ),
    );
    await tester.pumpAndSettle();

    final controller = Get.find<BridgeController>();
    controller.pairings.assignAll([
      const PairingProfile(
        id: 'pairing_navapi',
        name: 'navapi',
        baseUrl: 'https://navapi.navfirst.com/v1',
        spaceId: 'space_navapi',
        deviceName: 'navapi',
        deviceId: 'device_navapi',
        targetDeviceId: 'target_navapi',
        endpointType: 'app',
        deviceKey: '',
        endpointPublicKey: '',
        pairingToken: 'token_navapi',
        endpointGrant: '',
        tokenExpiresAt: 0,
        grantExpiresAt: 0,
      ),
    ]);
    await tester.pump();

    await tester.tap(find.text('navapi'));
    await tester.pump();

    expect(find.byType(PairingPage), findsOneWidget);
    expect(find.text('编辑配对'), findsOneWidget);
    expect(find.text('Relay 连接地址'), findsOneWidget);
  });
}
