import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/domain/roman_urdu.dart';

void main() {
  test('romanizes_common_words', () {
    expect(romanizeUrdu('اور ہے پہ میں'), 'aur hai pe mein');
  });

  test('romanizes_unknown_word_letter_by_letter', () {
    expect(romanizeUrdu('کتاب'), 'ktab');
  });

  test('keeps_line_breaks', () {
    expect(romanizeUrdu('علم بڑی دولت ہے\nوقت کی قدر کرو'), contains('\n'));
  });

  test('urdu_full_stop_becomes_period', () {
    expect(romanizeUrdu('محنت کامیابی کی کنجی ہے۔'), endsWith('hai.'));
  });

  test('urdu_comma_and_question_mark_become_latin', () {
    expect(romanizeUrdu('کیا، کیوں؟'), 'kya, kyun?');
  });

  test('has_at_least_150_word_overrides', () {
    expect(romanUrduWords.length, greaterThanOrEqualTo(150));
  });
}
