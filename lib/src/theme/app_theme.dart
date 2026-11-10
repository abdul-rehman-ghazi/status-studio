import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0E1311);
  static const surface = Color(0xFF18201C);
  static const accent = Color(0xFF3DD68C);
  static const onAccent = Color(0xFF06140D);
  static const textPrimary = Color(0xFFEEF3F0);
  static const textMuted = Color(0xFFA3AFA8);

  /// Drawn at partial opacity behind captions and the branding pill.
  static const overlay = Color(0xFF000000);
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
    final base = ThemeData(
      fontFamily: AppFonts.ui,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
    );
    return base.copyWith(listTileTheme: _listTiles(base.textTheme));
  }

  /// Rows one step below section labels (16 sp), with muted subtitles, so
  /// the hierarchy holds at large text sizes (spec §4). The styles come
  /// from the text theme to keep the Inter family.
  static ListTileThemeData _listTiles(TextTheme textTheme) {
    return ListTileThemeData(
      titleTextStyle: textTheme.bodyMedium?.copyWith(
        color: AppColors.textPrimary,
      ),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: AppColors.textMuted,
      ),
    );
  }
}
