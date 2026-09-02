import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../theme/recodex_theme.dart';

enum RecodexThemePreference {
  system('跟随系统', ThemeMode.system),
  light('浅色模式', ThemeMode.light),
  dark('深色模式', ThemeMode.dark),
  scheduled('按时间自动', ThemeMode.system);

  const RecodexThemePreference(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  String get description => switch (this) {
    RecodexThemePreference.system => '自动跟随设备的明暗外观',
    RecodexThemePreference.light => '保持清爽明亮的界面观感',
    RecodexThemePreference.dark => '减少夜间眩光，适合沉浸浏览',
    RecodexThemePreference.scheduled => '每天 07:00 使用浅色，18:00 切换深色',
  };

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
  static const _themeAccentKey = 'recodex_theme_accent';
  static const _fontScaleKey = 'recodex_font_scale';
  static const _highContrastKey = 'recodex_high_contrast';

  final preference = RecodexThemePreference.system.obs;
  final accent = RecodexThemeAccent.azure.obs;
  final fontScale = 1.0.obs;
  final highContrast = false.obs;
  final _clockTick = 0.obs;
  Timer? _clockTimer;

  ThemeMode get themeMode {
    if (preference.value == RecodexThemePreference.scheduled) {
      // Make the clock observable so the app rebuilds at the minute boundary.
      _clockTick.value;
      final hour = DateTime.now().hour;
      return hour >= 18 || hour < 7 ? ThemeMode.dark : ThemeMode.light;
    }
    return preference.value.themeMode;
  }

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

  @override
  void onClose() {
    _clockTimer?.cancel();
    super.onClose();
  }

  void setPreference(RecodexThemePreference value) {
    preference.value = value;
    _syncClockTimer();
    Get.changeThemeMode(themeMode);
    unawaited(_write(_themePreferenceKey, value.name));
  }

  void setHighContrast(bool value) {
    highContrast.value = value;
    Get.changeThemeMode(themeMode);
    unawaited(_write(_highContrastKey, '$value'));
  }

  void setAccent(RecodexThemeAccent value) {
    if (accent.value == value) return;
    accent.value = value;
    unawaited(_write(_themeAccentKey, value.name));
  }

  void setFontScale(double value) {
    final normalized = _fontScaleFromSlider(value);
    fontScale.value = normalized;
    unawaited(_write(_fontScaleKey, '$normalized'));
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
    final storedTheme = await _read(_themePreferenceKey);
    final themeValue = RecodexThemePreference.fromStorage(storedTheme);
    preference.value = themeValue;
    _syncClockTimer();
    Get.changeThemeMode(themeMode);

    final storedAccent = await _read(_themeAccentKey);
    accent.value = RecodexThemeAccent.fromStorage(storedAccent);

    final storedFontScale = await _read(_fontScaleKey);
    final parsedFontScale = double.tryParse(storedFontScale ?? '');
    if (parsedFontScale != null) {
      fontScale.value = parsedFontScale.clamp(0.9, 1.12);
    }
    final storedHighContrast = await _read(_highContrastKey);
    highContrast.value = storedHighContrast?.toLowerCase() == 'true';
    Get.changeThemeMode(themeMode);
  }

  void _syncClockTimer() {
    final shouldRun = preference.value == RecodexThemePreference.scheduled;
    if (shouldRun && _clockTimer == null) {
      _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _clockTick.value += 1;
        Get.changeThemeMode(themeMode);
      });
    } else if (!shouldRun) {
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Secure storage is unavailable in some desktop test targets. The
      // in-memory preference remains authoritative for the current session.
    }
  }
}
