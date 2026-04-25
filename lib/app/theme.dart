import 'package:flutter/material.dart';

class AegisColors {
  const AegisColors._();

  static const Color primary = Color(0xFF0B7A3E);
  static const Color primaryDark = Color(0xFF064E27);
  static const Color accent = Color(0xFFF4B942);
  static const Color danger = Color(0xFFD0342C);
  static const Color surface = Color(0xFFF6F5F1);
  static const Color surfaceDark = Color(0xFF121512);
  static const Color onSurface = Color(0xFF14231B);
  static const Color onSurfaceMuted = Color(0xFF5A6B62);
}

class AegisTheme {
  const AegisTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AegisColors.primary,
      brightness: Brightness.light,
      surface: AegisColors.surface,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AegisColors.surface,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.12,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(fontSize: 17, height: 1.4),
        bodyMedium: TextStyle(fontSize: 15, height: 1.4),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AegisColors.primary,
      brightness: Brightness.dark,
      surface: AegisColors.surfaceDark,
    );
    return light().copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AegisColors.surfaceDark,
    );
  }
}
