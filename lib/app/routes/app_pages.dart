import 'package:get/get.dart';

import '../pages/about/about_view.dart';
import '../pages/main/main_view.dart';
import '../pages/pairing/pairing_view.dart';
import '../pages/service/service_view.dart';
import '../pages/settings/settings_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const initial = Routes.main;

  static final routes = [
    GetPage(
      name: _Paths.main,
      page: () => const MainPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.pairing,
      page: () => const PairingPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.settings,
      page: () => const SettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.service,
      page: () => const ServicePage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.about,
      page: () => const AboutPage(),
      preventDuplicates: true,
    ),
  ];
}
