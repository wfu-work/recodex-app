import 'package:flutter/material.dart';

export 'recodex_icons.dart';

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

enum RecodexThemeAccent {
  azure(
    label: '天空蓝',
    description: 'Codex 风格的黑白中性主题',
    primary: Color(0xff171717),
    secondary: Color(0xff555555),
    darkPrimary: Color(0xfff5f5f5),
  ),
  amber(
    label: '日曜金',
    description: 'Codex 风格的黑白中性主题',
    primary: Color(0xff171717),
    secondary: Color(0xff555555),
    darkPrimary: Color(0xfff5f5f5),
  ),
  jade(
    label: '松石青',
    description: 'Codex 风格的黑白中性主题',
    primary: Color(0xff171717),
    secondary: Color(0xff555555),
    darkPrimary: Color(0xfff5f5f5),
  ),
  rose(
    label: '晚霞粉',
    description: 'Codex 风格的黑白中性主题',
    primary: Color(0xff171717),
    secondary: Color(0xff555555),
    darkPrimary: Color(0xfff5f5f5),
  );

  const RecodexThemeAccent({
    required this.label,
    required this.description,
    required this.primary,
    required this.secondary,
    required this.darkPrimary,
  });

  final String label;
  final String description;
  final Color primary;
  final Color secondary;
  final Color darkPrimary;

  static RecodexThemeAccent fromStorage(String? value) {
    return values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => azure,
    );
  }
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
      Color(0xfff5f5f5),
      Color(0xfffbfbfb),
      Color(0xfff2f2f2),
    ],
    backgroundStops: [0, 0.54, 1],
    primaryGlow: Color(0x00ffffff),
    secondaryGlow: Color(0x00ffffff),
    glassColor: Color(0xfff9f9f9),
    glassBorder: Color(0xffdedede),
    glassHighlight: Color(0xffffffff),
    glassShadow: Color(0x24000000),
    headerColor: Color(0xfffafafa),
    headerBorder: Color(0xffdedede),
    headerShadow: Color(0xff9a9a9a),
    text: Color(0xff171717),
    textMuted: Color(0xff6f6f6f),
    icon: Color(0xff171717),
    surfaceOverlay: Color(0xffeeeeee),
    userBubble: Color(0xffe9e9e9),
    assistantBubble: Color(0xfffafafa),
    errorBubble: Color(0xb8ffdad6),
    errorBorder: Color(0x2eba1a1a),
    success: Color(0xff0a8f43),
    error: Color(0xffba1a1a),
    warning: Color(0xffc47a00),
  );

  static const darkColors = RecodexThemeColors(
    backgroundGradient: [
      Color(0xff101010),
      Color(0xff171717),
      Color(0xff202020),
    ],
    backgroundStops: [0, 0.58, 1],
    primaryGlow: Color(0x00ffffff),
    secondaryGlow: Color(0x00ffffff),
    glassColor: Color(0xff242424),
    glassBorder: Color(0xff393939),
    glassHighlight: Color(0x18ffffff),
    glassShadow: Color(0x52000000),
    headerColor: Color(0xff181818),
    headerBorder: Color(0xff383838),
    headerShadow: Color(0xff000000),
    text: Color(0xfff5f5f5),
    textMuted: Color(0xffa4a4a4),
    icon: Color(0xfff5f5f5),
    surfaceOverlay: Color(0xff2b2b2b),
    userBubble: Color(0xff303030),
    assistantBubble: Color(0xff232323),
    errorBubble: Color(0xff382424),
    errorBorder: Color(0x66ff8a80),
    success: Color(0xff62d98b),
    error: Color(0xffff8a80),
    warning: Color(0xffffc35a),
  );

  static ThemeData get light => lightFor(RecodexThemeAccent.azure);

  static ThemeData lightFor(RecodexThemeAccent accent) {
    return _build(
      brightness: Brightness.light,
      colors: _lightColorsFor(accent),
      paper: const Color(0xfff5f5f5),
      surface: const Color(0xfffbfbfb),
      primary: const Color(0xff171717),
      secondary: const Color(0xff555555),
      outline: const Color(0xffd4d4d4),
    );
  }

  static ThemeData get dark => darkFor(RecodexThemeAccent.azure);

  static ThemeData darkFor(RecodexThemeAccent accent) {
    return _build(
      brightness: Brightness.dark,
      colors: _darkColorsFor(accent),
      paper: const Color(0xff101010),
      surface: const Color(0xff1d1d1d),
      primary: const Color(0xfff5f5f5),
      secondary: const Color(0xffc8c8c8),
      outline: const Color(0xff505050),
    );
  }

  static RecodexThemeColors _lightColorsFor(RecodexThemeAccent accent) {
    // Accent remains in the API for saved settings compatibility. Codex's
    // mobile visual language uses a neutral black-and-white treatment.
    return lightColors;
  }

  static RecodexThemeColors _darkColorsFor(RecodexThemeAccent accent) {
    return darkColors;
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
      iconTheme: IconThemeData(color: colors.icon, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.icon),
          iconSize: const WidgetStatePropertyAll(20),
        ),
      ),
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
          foregroundColor: isDark ? const Color(0xff171717) : Colors.white,
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
        color: isDark ? const Color(0xff252525) : const Color(0xfffbfbfb),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? const Color(0xff3b3b3b) : const Color(0xffdedede),
          ),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 7),
        elevation: isDark ? 12 : 6,
        shadowColor: isDark
            ? Colors.black.withValues(alpha: 0.46)
            : const Color(0x29333333),
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
          color: colors.text,
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.disabled)
                ? colors.textMuted.withValues(alpha: 0.52)
                : colors.text,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
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
