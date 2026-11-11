import 'package:flutter/material.dart';

/// One theme's colours (spec FR-32). Widgets read them with
/// `context.palette`, so they follow the theme the user chose.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textMuted,
  });

  static const dark = AppPalette(
    background: Color(0xFF0E1311),
    surface: Color(0xFF18201C),
    accent: Color(0xFF3DD68C),
    onAccent: Color(0xFF06140D),
    textPrimary: Color(0xFFEEF3F0),
    textMuted: Color(0xFFA3AFA8),
  );

  /// One deeper green on a soft mint page: the bright green reads at only
  /// 1.9:1 as text on white (spec FR-32).
  static const light = AppPalette(
    background: Color(0xFFF5F8F6),
    surface: Color(0xFFFFFFFF),
    accent: Color(0xFF0F7D4C),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0E1311),
    textMuted: Color(0xFF5B6862),
  );

  /// The page behind every screen.
  final Color background;

  /// Cards, panels and the area around a video.
  final Color surface;
  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color textMuted;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? accent,
    Color? onAccent,
    Color? textPrimary,
    Color? textMuted,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  /// Lets a theme change animate instead of jumping.
  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) {
      return this;
    }
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

extension AppPaletteOf on BuildContext {
  /// The current theme's colours; every app theme carries them.
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// The Trim logo's colours (spec §7): the same in both themes, as on the
/// launcher icon.
abstract final class LogoColors {
  static const tile = Color(0xFF3DD68C);
  static const ink = Color(0xFF06140D);
}

/// The exported reel's caption and branding colours, shared by the overlay
/// PNG and the reel preview. They never follow the theme, so a reel looks
/// the same whichever theme made it (spec FR-32).
abstract final class ReelColors {
  static const text = Color(0xFFEEF3F0);

  /// Drawn at partial opacity behind captions and the branding pill.
  static const scrim = Color(0xFF000000);

  // Caption looks (spec FR-7, M37).
  static const captionPaper = Color(0xFFFFFFFF);
  static const captionInk = Color(0xFF111111);
  static const captionYellow = Color(0xFFFFD84D);
  static const captionGold = Color(0xFFF2C879);
  static const captionGreen = Color(0xFF0A5A3C);
}

/// Marks drawn on the video picture: the crop frame and its handle, face
/// and body markers, the spot pin, scrims under player controls. The
/// picture, not the page, is behind them, so they keep their dark-theme
/// colours in both themes (spec FR-32).
abstract final class PictureMarkColors {
  static const accent = Color(0xFF3DD68C);
  static const onAccent = Color(0xFF06140D);
  static const light = Color(0xFFEEF3F0);
  static const onLight = Color(0xFF0E1311);
  static const scrim = Color(0xFF000000);
}

/// Font families bundled in `assets/fonts`, registered in `pubspec.yaml`.
abstract final class AppFonts {
  static const ui = 'Inter';
  static const nastaliq = 'NotoNastaliqUrdu';
  static const naskh = 'NotoNaskhArabic';
}

abstract final class AppTheme {
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  /// The two themes differ in colour only (spec FR-32).
  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: brightness,
        ).copyWith(
          primary: palette.accent,
          onPrimary: palette.onAccent,
          surface: palette.background,
          onSurface: palette.textPrimary,
          onSurfaceVariant: palette.textMuted,
          surfaceContainer: palette.surface,
        );
    final base = ThemeData(
      fontFamily: AppFonts.ui,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      extensions: [palette],
    );
    return base.copyWith(listTileTheme: _listTiles(base.textTheme, palette));
  }

  /// Rows one step below section labels (16 sp), with muted subtitles, so
  /// the hierarchy holds at large text sizes (spec §4). The styles come
  /// from the text theme to keep the Inter family.
  static ListTileThemeData _listTiles(TextTheme textTheme, AppPalette palette) {
    return ListTileThemeData(
      titleTextStyle: textTheme.bodyMedium?.copyWith(
        color: palette.textPrimary,
      ),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: palette.textMuted,
      ),
    );
  }
}
