part of 'app_pages.dart';

abstract class Routes {
  static const main = _Paths.main;
  static const pairing = _Paths.pairing;
  static const settings = _Paths.settings;
  static const service = _Paths.service;
  static const about = _Paths.about;

  Routes._();
}

abstract class _Paths {
  static const main = '/';
  static const pairing = '/pairing';
  static const settings = '/settings';
  static const service = '/service';
  static const about = '/about';
}
