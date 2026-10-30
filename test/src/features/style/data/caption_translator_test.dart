import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/data/caption_translator.dart';

void main() {
  const translator = MlKitCaptionTranslator();

  test('supports_urdu_arabic_persian_hindi_bengali', () {
    expect(
      ['ur', 'ar', 'fa', 'hi', 'bn'].every(translator.supports),
      isTrue,
    );
  });

  test('does_not_support_punjabi', () {
    expect(translator.supports('pa'), isFalse);
  });

  test('does_not_translate_english_to_english', () {
    expect(translator.supports('en'), isFalse);
  });
}
