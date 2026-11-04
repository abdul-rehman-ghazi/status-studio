import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/export/domain/reel_file_name.dart';

void main() {
  test('name_is_kalam_start_and_end_with_two_words_each', () {
    final stem = reelFileStem(
      videoTitle: 'Arsh e Haq Hai Masnad e Rifat | Owais Raza Qadri',
      captionText: 'علم بڑی دولت ہے\nمحنت کامیابی کی کنجی ہے\nوقت کی قدر کرو',
    );

    expect(stem, 'Arsh_e-علم_بڑی-وقت_کی');
  });

  test('title_noise_is_left_out_of_the_kalam', () {
    final stem = reelFileStem(
      videoTitle: '(Official Video) Wah Kya Jood o Karam [HD]',
      captionText: 'a b c',
    );

    expect(stem, 'Wah_Kya-a_b-a_b');
  });

  test('kalam_drops_a_bar_and_everything_after_it', () {
    final stem = reelFileStem(
      videoTitle: 'Rick Astley - Never Gonna (4K) | Remastered',
      captionText: 'a b c',
    );

    expect(stem, 'Rick_Astley-a_b-a_b');
  });

  test('a_one_line_caption_uses_it_for_start_and_end', () {
    final stem = reelFileStem(videoTitle: 'Naat', captionText: 'one two three');

    expect(stem, 'Naat-one_two-one_two');
  });

  test('punctuation_and_illegal_characters_are_dropped', () {
    final stem = reelFileStem(
      videoTitle: 'Naat',
      captionText: 'کیا؟ "جود/و" کرم،\nآخر: شعر۔',
    );

    expect(stem, 'Naat-کیا_جودو-آخر_شعر');
  });

  test('a_part_with_no_words_is_left_out', () {
    final stem = reelFileStem(videoTitle: 'Naat', captionText: '  ');

    expect(stem, 'Naat');
  });

  test('nothing_to_name_it_by_falls_back_to_reel', () {
    final stem = reelFileStem(videoTitle: '(HD)', captionText: '');

    expect(stem, 'reel');
  });
}
