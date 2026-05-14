import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/app.dart';
import 'app/controllers/bridge_controller.dart';

void main() {
  Get.put(BridgeController(), permanent: true);
  Get.put(ThemeController(), permanent: true);
  runApp(const RecodexApp());
}

class RecodexApp extends StatelessWidget {
  const RecodexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetX<ThemeController>(
      builder: (themeController) {
        final fontScale = themeController.fontScale.value;
        return GetMaterialApp(
          title: 'Remote Codex Companion',
          debugShowCheckedModeBanner: false,
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
          home: const MainPage(),
        );
      },
    );
  }
}
