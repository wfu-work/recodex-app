part of 'app_pages.dart';

abstract class Routes {
  static const main = _Paths.main;
  static const pairing = _Paths.pairing;
  static const settings = _Paths.settings;
  static const connectionSettings = _Paths.connectionSettings;
  static const taskSettings = _Paths.taskSettings;
  static const taskHistory = _Paths.taskHistory;
  static const usageStatistics = _Paths.usageStatistics;
  static const conversationDisplay = _Paths.conversationDisplay;
  static const shortcuts = _Paths.shortcuts;
  static const securitySettings = _Paths.securitySettings;
  static const theme = _Paths.theme;
  static const notifications = _Paths.notifications;
  static const service = _Paths.service;
  static const about = _Paths.about;
  static const licenses = _Paths.licenses;
  static const gitDiff = _Paths.gitDiff;

  Routes._();
}

abstract class _Paths {
  static const main = '/';
  static const pairing = '/pairing';
  static const settings = '/settings';
  static const connectionSettings = '/settings/connection';
  static const taskSettings = '/settings/tasks';
  static const taskHistory = '/settings/tasks/history';
  static const usageStatistics = '/settings/usage';
  static const conversationDisplay = '/settings/tasks/display';
  static const shortcuts = '/settings/shortcuts';
  static const securitySettings = '/settings/security';
  static const theme = '/settings/theme';
  static const notifications = '/settings/notifications';
  static const service = '/service';
  static const about = '/about';
  static const licenses = '/about/licenses';
  static const gitDiff = '/git-diff';
}
