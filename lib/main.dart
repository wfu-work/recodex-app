import 'package:flutter/material.dart';

import 'app/app.dart';
import 'configs/app_initializer.dart';

export 'app/app.dart';

Future<void> main() async {
  await AppInitializer.init();
  runApp(const RecodexApp());
}
