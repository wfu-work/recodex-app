import 'package:flutter/material.dart';

class RecodexTheme {
  static ThemeData get light {
    const paper = Color(0xfffcf8f8);
    const surface = Color(0xffffffff);
    const ink = Color(0xff1c1b1b);
    const primary = Color(0xff005fc7);

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Sora',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        surface: surface,
        primary: primary,
        secondary: const Color(0xff007aff),
        outline: const Color(0xffc4c7c8),
      ),
      scaffoldBackgroundColor: paper,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 42,
          height: 1.08,
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: -0.6,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: -0.2,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: ink),
        titleMedium: TextStyle(fontWeight: FontWeight.w800, color: ink),
        titleSmall: TextStyle(fontWeight: FontWeight.w700, color: ink),
        bodyMedium: TextStyle(height: 1.55, color: ink),
        labelLarge: TextStyle(fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.74),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: Color(0x66ffffff)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: Color(0xff007aff), width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.72),
        indicatorColor: const Color(0x1f007aff),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
