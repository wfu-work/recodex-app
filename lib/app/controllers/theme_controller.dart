import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

enum RecodexThemePreference {
  system('跟随系统', ThemeMode.system),
  light('浅色', ThemeMode.light),
  dark('深色', ThemeMode.dark);

  const RecodexThemePreference(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  static RecodexThemePreference fromLabel(String label) {
    return values.firstWhere(
      (preference) => preference.label == label,
      orElse: () => system,
    );
  }

  static RecodexThemePreference fromStorage(String? value) {
    return values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => system,
    );
  }
}

class ThemeController extends GetxController {
  static const _storage = FlutterSecureStorage();
  static const _themePreferenceKey = 'recodex_theme_preference';
  static const _fontScaleKey = 'recodex_font_scale';

  final preference = RecodexThemePreference.system.obs;
  final fontScale = 1.0.obs;

  ThemeMode get themeMode => preference.value.themeMode;
  String get fontSizeLabel {
    final value = fontScale.value;
    if (value <= 0.92) return '小';
    if (value >= 1.08) return '大';
    return '标准';
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadSettings());
  }

  void setPreference(RecodexThemePreference value) {
    preference.value = value;
    Get.changeThemeMode(value.themeMode);
    unawaited(_storage.write(key: _themePreferenceKey, value: value.name));
  }

  void setFontScale(double value) {
    final normalized = _fontScaleFromSlider(value);
    fontScale.value = normalized;
    unawaited(_storage.write(key: _fontScaleKey, value: '$normalized'));
  }

  double fontScaleToSliderValue() {
    if (fontScale.value <= 0.92) return 0;
    if (fontScale.value >= 1.08) return 2;
    return 1;
  }

  double _fontScaleFromSlider(double value) {
    return switch (value.round()) {
      0 => 0.9,
      1 => 1.0,
      _ => 1.12,
    };
  }

  Future<void> _loadSettings() async {
    final storedTheme = await _storage.read(key: _themePreferenceKey);
    final themeValue = RecodexThemePreference.fromStorage(storedTheme);
    preference.value = themeValue;
    Get.changeThemeMode(themeValue.themeMode);

    final storedFontScale = await _storage.read(key: _fontScaleKey);
    final parsedFontScale = double.tryParse(storedFontScale ?? '');
    if (parsedFontScale != null) {
      fontScale.value = parsedFontScale.clamp(0.9, 1.12);
    }
  }
}
