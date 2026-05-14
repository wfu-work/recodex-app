import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../configs/global_binding.dart';
import 'pages/settings/theme_controller.dart';
import 'routes/app_pages.dart';
import 'theme/recodex_theme.dart';

class RecodexApp extends StatelessWidget {
  const RecodexApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.isRegistered<ThemeController>()
        ? Get.find<ThemeController>()
        : Get.put<ThemeController>(ThemeController(), permanent: true);
    return Obx(() {
      final fontScale = themeController.fontScale.value;
      return GetMaterialApp(
        title: 'Remote Codex Companion',
        debugShowCheckedModeBanner: false,
        initialBinding: GlobalBinding(),
        getPages: AppPages.routes,
        initialRoute: AppPages.initial,
        defaultTransition: Transition.cupertino,
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        themeMode: themeController.themeMode,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(fontScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
    });
  }
}
