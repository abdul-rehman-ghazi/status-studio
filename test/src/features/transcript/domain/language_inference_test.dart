import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/domain/language_inference.dart';

void main() {
  test('urdu_letters_infer_ur', () {
    expect(inferLanguageCode('یہ اچھی بات ہے'), 'ur');
  });

  test('persian_letters_without_urdu_infer_fa', () {
    expect(inferLanguageCode('چگونه'), 'fa');
  });

  test('plain_arabic_infers_ar', () {
    expect(inferLanguageCode('السلام عليكم'), 'ar');
  });

  test('devanagari_infers_hi', () {
    expect(inferLanguageCode('नमस्ते'), 'hi');
  });

  test('bengali_infers_bn', () {
    expect(inferLanguageCode('নমস্কার'), 'bn');
  });

  test('gurmukhi_infers_pa', () {
    expect(inferLanguageCode('ਸਤ ਸ੍ਰੀ ਅਕਾਲ'), 'pa');
  });

  test('latin_infers_en', () {
    expect(inferLanguageCode('Patience pays'), 'en');
  });

  test('unknown_script_infers_und', () {
    expect(inferLanguageCode('你好'), 'und');
  });
}
