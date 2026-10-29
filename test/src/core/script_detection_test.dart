import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/script_detection.dart';

void main() {
  test('urdu_letters_are_detected', () {
    expect(containsUrduLetters('علم بڑی دولت ہے'), isTrue);
  });

  test('arabic_script_without_urdu_only_letters_is_not_urdu', () {
    expect(containsUrduLetters('السلام عليكم'), isFalse);
  });

  test('arabic_script_is_detected', () {
    expect(isArabicScript('Hello سلام'), isTrue);
  });

  test('latin_text_is_not_arabic_script', () {
    expect(isArabicScript('Hello'), isFalse);
  });
}
