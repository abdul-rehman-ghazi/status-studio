import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Caption font by script (spec §6.5).
String captionFontFamily(String text) {
  if (containsUrduLetters(text)) {
    return AppFonts.nastaliq;
  }
  if (isArabicScript(text)) {
    return AppFonts.naskh;
  }
  return AppFonts.ui;
}

/// Line height for [text]'s caption font (spec FR-7): Nastaliq's letters
/// collide below about 2.1.
double captionLineHeight(String text) =>
    captionFontFamily(text) == AppFonts.nastaliq ? 2.1 : 1.3;
