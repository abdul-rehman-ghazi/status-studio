import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/domain/caption_font.dart';
import 'package:status_studio/src/theme/app_theme.dart';

void main() {
  test('urdu_text_uses_nastaliq', () {
    expect(captionFontFamily('صبر کا پھل میٹھا ہوتا ہے'), AppFonts.nastaliq);
  });

  test('arabic_text_uses_naskh', () {
    expect(captionFontFamily('السلام عليكم'), AppFonts.naskh);
  });

  test('latin_text_uses_inter', () {
    expect(captionFontFamily('Patience pays'), AppFonts.ui);
  });
}
