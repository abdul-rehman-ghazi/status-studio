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
