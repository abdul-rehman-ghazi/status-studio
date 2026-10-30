import 'package:status_studio/src/core/script_detection.dart';

/// Whisper's language code for [text], read from its script (spec §6.4);
/// `und` when no rule matches.
String inferLanguageCode(String text) {
  if (isArabicScript(text)) {
    return _arabicScriptLanguage(text);
  }
  if (isDevanagari(text)) {
    return 'hi';
  }
  if (isBengaliScript(text)) {
    return 'bn';
  }
  if (isGurmukhi(text)) {
    return 'pa';
  }
  if (isLatinScript(text)) {
    return 'en';
  }
  return 'und';
}

String _arabicScriptLanguage(String text) {
  if (containsUrduLetters(text)) {
    return 'ur';
  }
  return containsPersianLetters(text) ? 'fa' : 'ar';
}
