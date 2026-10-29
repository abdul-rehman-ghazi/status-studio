import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0E1311);
  static const surface = Color(0xFF18201C);
  static const accent = Color(0xFF3DD68C);
  static const onAccent = Color(0xFF06140D);
  static const textPrimary = Color(0xFFEEF3F0);
  static const textMuted = Color(0xFFA3AFA8);
}

/// Font families bundled in `assets/fonts`, registered in `pubspec.yaml`.
abstract final class AppFonts {
  static const ui = 'Inter';
  static const nastaliq = 'NotoNastaliqUrdu';
  static const naskh = 'NotoNaskhArabic';
}

abstract final class AppTheme {
  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          surface: AppColors.background,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textMuted,
          surfaceContainer: AppColors.surface,
        );
    return ThemeData(
      fontFamily: AppFonts.ui,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
    );
  }
}
