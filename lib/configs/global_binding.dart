import 'package:get/get.dart';

import '../app/pages/main/bridge_controller.dart';
import '../app/pages/settings/settings_preferences_controller.dart';
import '../app/pages/settings/theme_controller.dart';
import '../app/services/task_notification_controller.dart';

class GlobalBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SettingsPreferencesController>()) {
      Get.put<SettingsPreferencesController>(
        SettingsPreferencesController(),
        permanent: true,
      );
    }
    if (!Get.isRegistered<BridgeController>()) {
      Get.put<BridgeController>(BridgeController(), permanent: true);
    }
    if (!Get.isRegistered<ThemeController>()) {
      Get.put<ThemeController>(ThemeController(), permanent: true);
    }
    if (!Get.isRegistered<TaskNotificationController>()) {
      Get.put<TaskNotificationController>(
        TaskNotificationController(),
        permanent: true,
      );
    }
  }
}
