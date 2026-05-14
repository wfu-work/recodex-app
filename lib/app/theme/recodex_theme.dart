import 'package:flutter/material.dart';

@immutable
class RecodexThemeColors extends ThemeExtension<RecodexThemeColors> {
  const RecodexThemeColors({
    required this.backgroundGradient,
    required this.backgroundStops,
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.glassColor,
    required this.glassBorder,
    required this.glassHighlight,
    required this.glassShadow,
    required this.headerColor,
    required this.headerBorder,
    required this.headerShadow,
    required this.text,
    required this.textMuted,
    required this.icon,
    required this.surfaceOverlay,
    required this.userBubble,
    required this.assistantBubble,
    required this.errorBubble,
    required this.errorBorder,
    required this.success,
    required this.error,
    required this.warning,
  });

  final List<Color> backgroundGradient;
  final List<double> backgroundStops;
  final Color primaryGlow;
  final Color secondaryGlow;
  final Color glassColor;
  final Color glassBorder;
  final Color glassHighlight;
  final Color glassShadow;
  final Color headerColor;
  final Color headerBorder;
  final Color headerShadow;
  final Color text;
  final Color textMuted;
  final Color icon;
  final Color surfaceOverlay;
  final Color userBubble;
  final Color assistantBubble;
  final Color errorBubble;
  final Color errorBorder;
  final Color success;
  final Color error;
  final Color warning;

  @override
  RecodexThemeColors copyWith({
    List<Color>? backgroundGradient,
    List<double>? backgroundStops,
    Color? primaryGlow,
    Color? secondaryGlow,
    Color? glassColor,
    Color? glassBorder,
    Color? glassHighlight,
    Color? glassShadow,
    Color? headerColor,
    Color? headerBorder,
    Color? headerShadow,
    Color? text,
    Color? textMuted,
    Color? icon,
    Color? surfaceOverlay,
    Color? userBubble,
    Color? assistantBubble,
    Color? errorBubble,
    Color? errorBorder,
    Color? success,
    Color? error,
    Color? warning,
  }) {
    return RecodexThemeColors(
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      backgroundStops: backgroundStops ?? this.backgroundStops,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      secondaryGlow: secondaryGlow ?? this.secondaryGlow,
      glassColor: glassColor ?? this.glassColor,
      glassBorder: glassBorder ?? this.glassBorder,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      glassShadow: glassShadow ?? this.glassShadow,
      headerColor: headerColor ?? this.headerColor,
      headerBorder: headerBorder ?? this.headerBorder,
      headerShadow: headerShadow ?? this.headerShadow,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      icon: icon ?? this.icon,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      userBubble: userBubble ?? this.userBubble,
      assistantBubble: assistantBubble ?? this.assistantBubble,
      errorBubble: errorBubble ?? this.errorBubble,
      errorBorder: errorBorder ?? this.errorBorder,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
    );
  }

  @override
  RecodexThemeColors lerp(ThemeExtension<RecodexThemeColors>? other, double t) {
    if (other is! RecodexThemeColors) return this;
    return RecodexThemeColors(
      backgroundGradient: List.generate(
        backgroundGradient.length,
        (index) => Color.lerp(
          backgroundGradient[index],
          other.backgroundGradient[index],
          t,
        )!,
      ),
      backgroundStops: backgroundStops,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      secondaryGlow: Color.lerp(secondaryGlow, other.secondaryGlow, t)!,
      glassColor: Color.lerp(glassColor, other.glassColor, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      headerColor: Color.lerp(headerColor, other.headerColor, t)!,
      headerBorder: Color.lerp(headerBorder, other.headerBorder, t)!,
      headerShadow: Color.lerp(headerShadow, other.headerShadow, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      assistantBubble: Color.lerp(assistantBubble, other.assistantBubble, t)!,
      errorBubble: Color.lerp(errorBubble, other.errorBubble, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension RecodexThemeContext on BuildContext {
  RecodexThemeColors get recodexColors =>
      Theme.of(this).extension<RecodexThemeColors>()!;
}

class RecodexTheme {
  static const _fontFamily = '.SF Pro Text';
  static const _fallbackFonts = [
    '.SF Pro Text',
    '.SF Pro Display',
    'SF Pro Text',
    'SF Pro Display',
    'PingFang SC',
    'Helvetica Neue',
    'Arial',
  ];

  static const lightColors = RecodexThemeColors(
    backgroundGradient: [
      Color(0xffeef5ff),
      Color(0xfff8f9fc),
      Color(0xfffff7fb),
    ],
    backgroundStops: [0, 0.54, 1],
    primaryGlow: Color(0x80dbeaff),
    secondaryGlow: Color(0x94ffeaf6),
    glassColor: Color(0xa3ffffff),
    glassBorder: Color(0xb8ffffff),
    glassHighlight: Color(0xadffffff),
    glassShadow: Color(0x218b95a5),
    headerColor: Color(0xffffffff),
    headerBorder: Color(0xffd8dee8),
    headerShadow: Color(0xff9da8b7),
    text: Color(0xff111318),
    textMuted: Color(0xff747878),
    icon: Color(0xff005fc7),
    surfaceOverlay: Color(0x99ffffff),
    userBubble: Color(0x14202124),
    assistantBubble: Color(0xa8ffffff),
    errorBubble: Color(0xb8ffdad6),
    errorBorder: Color(0x2eba1a1a),
    success: Color(0xff0a8f43),
    error: Color(0xffba1a1a),
    warning: Color(0xffc47a00),
  );

  static const darkColors = RecodexThemeColors(
    backgroundGradient: [
      Color(0xff0b1020),
      Color(0xff111827),
      Color(0xff201525),
    ],
    backgroundStops: [0, 0.58, 1],
    primaryGlow: Color(0x66448fff),
    secondaryGlow: Color(0x4dff6eb7),
    glassColor: Color(0x8f1b2432),
    glassBorder: Color(0x40ffffff),
    glassHighlight: Color(0x24ffffff),
    glassShadow: Color(0x8a000000),
    headerColor: Color(0xff111827),
    headerBorder: Color(0xff314052),
    headerShadow: Color(0xff000000),
    text: Color(0xfff4f7fb),
    textMuted: Color(0xffa9b3c2),
    icon: Color(0xff70b7ff),
    surfaceOverlay: Color(0x661b2432),
    userBubble: Color(0x99304255),
    assistantBubble: Color(0x991b2432),
    errorBubble: Color(0x803b1d24),
    errorBorder: Color(0x66ff8a80),
    success: Color(0xff62d98b),
    error: Color(0xffff8a80),
    warning: Color(0xffffc35a),
  );

  static ThemeData get light {
    return _build(
      brightness: Brightness.light,
      colors: lightColors,
      paper: const Color(0xfff7f8fb),
      surface: const Color(0xffffffff),
      primary: const Color(0xff007aff),
      secondary: const Color(0xff5e5ce6),
      outline: const Color(0xffd6d9df),
    );
  }

  static ThemeData get dark {
    return _build(
      brightness: Brightness.dark,
      colors: darkColors,
      paper: const Color(0xff0b1020),
      surface: const Color(0xff151d2b),
      primary: const Color(0xff70b7ff),
      secondary: const Color(0xffa6a4ff),
      outline: const Color(0xff3d4a5f),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required RecodexThemeColors colors,
    required Color paper,
    required Color surface,
    required Color primary,
    required Color secondary,
    required Color outline,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: surface,
      primary: primary,
      secondary: secondary,
      outline: outline,
      error: colors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fallbackFonts,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      extensions: [colors],
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 42,
          height: 1.06,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        headlineMedium: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        headlineSmall: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: colors.text),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: colors.text),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, color: colors.text),
        bodyLarge: TextStyle(height: 1.5, color: colors.text),
        bodyMedium: TextStyle(height: 1.5, color: colors.text),
        bodySmall: TextStyle(color: colors.textMuted),
        labelLarge: TextStyle(fontWeight: FontWeight.w700, color: colors.text),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colors.text,
          fontFamily: '.SF Pro Display',
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: colors.icon),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceOverlay,
        hintStyle: TextStyle(color: colors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: primary, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.34)),
          shape: const StadiumBorder(),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceOverlay,
        indicatorColor: primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: colors.text,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xff202a3a) : Colors.white,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: outline.withValues(alpha: 0.55),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : colors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.32)
              : outline.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
