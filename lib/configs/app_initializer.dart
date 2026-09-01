import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../app/pages/main/bridge_controller.dart';
import '../app/pages/settings/settings_preferences_controller.dart';
import '../app/pages/settings/theme_controller.dart';
import '../app/services/task_notification_controller.dart';

class AppInitializer {
  const AppInitializer._();

  static Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await BridgeController.initializeStorage();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Color(0x00000000)),
    );
    _putIfAbsent<SettingsPreferencesController>(
      () => SettingsPreferencesController(),
    );
    _putIfAbsent<BridgeController>(() => BridgeController());
    _putIfAbsent<ThemeController>(() => ThemeController());
    _putIfAbsent<TaskNotificationController>(
      () => TaskNotificationController(),
    );
  }

  static void _putIfAbsent<T extends Object>(T Function() builder) {
    if (!Get.isRegistered<T>()) {
      Get.put<T>(builder(), permanent: true);
    }
  }
}
