import 'package:get/get.dart';

import '../pages/about/about_view.dart';
import '../pages/about/open_source_licenses_view.dart';
import '../pages/main/git_diff_view.dart';
import '../pages/main/main_view.dart';
import '../pages/pairing/pairing_view.dart';
import '../pages/service/service_view.dart';
import '../pages/settings/settings_view.dart';
import '../pages/settings/connection_settings_view.dart';
import '../pages/settings/notification_settings_view.dart';
import '../pages/settings/security_settings_view.dart';
import '../pages/settings/task_settings_view.dart';
import '../pages/settings/task_history_view.dart';
import '../pages/settings/usage_statistics_view.dart';
import '../pages/settings/conversation_display_settings_view.dart';
import '../pages/settings/shortcuts_settings_view.dart';
import '../pages/settings/theme_settings_view.dart';

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
      name: _Paths.connectionSettings,
      page: () => const ConnectionSettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.taskSettings,
      page: () => const TaskSettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.taskHistory,
      page: () => const TaskHistoryPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.usageStatistics,
      page: () => const UsageStatisticsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.conversationDisplay,
      page: () => const ConversationDisplaySettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.shortcuts,
      page: () => const ShortcutsSettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.securitySettings,
      page: () => const SecuritySettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.theme,
      page: () => const ThemeSettingsPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.notifications,
      page: () => const NotificationSettingsPage(),
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
    GetPage(
      name: _Paths.licenses,
      page: () => const OpenSourceLicensesPage(),
      preventDuplicates: true,
    ),
    GetPage(
      name: _Paths.gitDiff,
      page: () => const GitDiffPage(),
      preventDuplicates: true,
    ),
  ];
}
