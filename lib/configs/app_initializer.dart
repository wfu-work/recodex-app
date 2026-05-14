import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../app/controllers/bridge_controller.dart';
import '../app/controllers/theme_controller.dart';

class AppInitializer {
  const AppInitializer._();

  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Color(0x00000000)),
    );
    _putIfAbsent<BridgeController>(() => BridgeController());
    _putIfAbsent<ThemeController>(() => ThemeController());
  }

  static void _putIfAbsent<T extends Object>(T Function() builder) {
    if (!Get.isRegistered<T>()) {
      Get.put<T>(builder(), permanent: true);
    }
  }
}
