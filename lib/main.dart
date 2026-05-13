import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/app.dart';
import 'app/controllers/bridge_controller.dart';

void main() {
  runApp(const RecodexApp());
}

class RecodexApp extends StatelessWidget {
  const RecodexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Remote Codex Companion',
      debugShowCheckedModeBanner: false,
      initialBinding: BindingsBuilder(() {
        Get.put(BridgeController(), permanent: true);
      }),
      theme: RecodexTheme.light,
      home: const MainPage(),
    );
  }
}
