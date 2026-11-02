import 'package:status_studio/src/features/style/data/caption_translator.dart';

/// Supports what ML Kit supports for the app's languages (not Punjabi);
/// "translates" by tagging the text.
class FakeCaptionTranslator implements CaptionTranslator {
  const FakeCaptionTranslator();

  @override
  bool supports(String languageCode) =>
      const {'ur', 'ar', 'fa', 'hi', 'bn'}.contains(languageCode);

  @override
  Future<String> toEnglish(String text, String languageCode) async =>
      'EN: $text';
}
