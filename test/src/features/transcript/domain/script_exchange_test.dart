import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const script = Transcript(
  languageCode: 'ur',
  lines: [
    TranscriptLine(
      index: 0,
      text: 'غلط ایک',
      start: Duration(seconds: 21, milliseconds: 400),
      end: Duration(seconds: 30),
    ),
    TranscriptLine(
      index: 1,
      text: 'غلط دو',
      start: Duration(seconds: 31),
      end: Duration(seconds: 39, milliseconds: 500),
    ),
  ],
);

List<String> textsOf(CorrectedScript corrected) =>
    corrected.transcript.lines.map((line) => line.text).toList();

void main() {
  test('prompt_holds_the_video_and_every_row_with_times', () {
    final prompt = scriptPromptFor(
      videoTitle: 'Some Naat',
      videoUrl: 'https://youtu.be/abc',
      lines: script.lines,
    );

    expect(prompt, contains('Video title: Some Naat'));
    expect(prompt, contains('1 | 00:21.40 | 00:30.00 | غلط ایک'));
    expect(prompt, contains('2 | 00:31.00 | 00:39.50 | غلط دو'));
  });

  test('reply_text_replaces_lines_matched_by_number', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 00:21.40 | 00:30.00 | صحیح ایک\n2 | 00:31.00 | 00:39.50 | صحیح دو',
    );

    expect(textsOf(corrected), ['صحیح ایک', 'صحیح دو']);
  });

  test('times_always_come_from_the_current_script', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 09:99.99 | 09:99.99 | صحیح ایک',
    );

    expect(corrected.transcript.lines.first.start, script.lines.first.start);
  });

  test('code_fences_and_chatter_around_the_rows_are_ignored', () {
    final corrected = applyCorrectedScript(
      script,
      'Here you go:\n```\n2 | 00:31.00 | 00:39.50 | صحیح دو\n```\nSources: x',
    );

    expect(textsOf(corrected), ['غلط ایک', 'صحیح دو']);
  });

  test('rows_missing_from_the_reply_keep_their_text', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 00:21.40 | 00:30.00 | صحیح ایک',
    );

    expect(textsOf(corrected), ['صحیح ایک', 'غلط دو']);
  });

  test('question_marked_rows_are_kept_and_listed', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 00:21.40 | 00:30.00 | غلط ایک [?]',
    );

    expect(textsOf(corrected).first, 'غلط ایک');
    expect(corrected.uncertainRows, [1]);
  });

  test('changed_lines_count_only_rows_whose_text_differs', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 00:21.40 | 00:30.00 | غلط ایک\n2 | 00:31.00 | 00:39.50 | صحیح دو',
    );

    expect(corrected.changedLines, 1);
  });

  test('text_with_a_bar_in_it_stays_whole', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 00:21.40 | 00:30.00 | a | b',
    );

    expect(textsOf(corrected).first, 'a | b');
  });

  test('a_reply_without_rows_is_rejected', () {
    expect(
      () => applyCorrectedScript(script, 'Sorry, I cannot do that.'),
      throwsA(isA<NoScriptRowsException>()),
    );
  });

  Transcript longScript(int lineCount) => Transcript(
    languageCode: 'ur',
    lines: [
      for (var index = 0; index < lineCount; index++)
        TranscriptLine(
          index: index,
          text: 'line $index',
          start: Duration(seconds: index * 5),
          end: Duration(seconds: index * 5 + 4),
        ),
    ],
  );

  test('lines_to_check_are_the_picked_range_even_in_a_long_script', () {
    final lines = linesToCheck(longScript(225), const RangeSelected(100, 104));

    expect(lines.map((line) => line.index), [100, 101, 102, 103, 104]);
  });

  test('lines_to_check_are_the_whole_script_when_it_is_short', () {
    final lines = linesToCheck(longScript(mostLinesForAi), const NoSelection());

    expect(lines, hasLength(mostLinesForAi));
  });

  test('a_long_script_with_no_pick_is_too_long_for_an_ai', () {
    expect(
      () => linesToCheck(longScript(225), const NoSelection()),
      throwsA(isA<TooManyLinesForAiException>()),
    );
  });

  test('a_picked_range_over_the_limit_is_too_long_for_an_ai', () {
    expect(
      () => linesToCheck(longScript(225), const RangeSelected(0, 60)),
      throwsA(isA<TooManyLinesForAiException>()),
    );
  });

  test('groq_takes_thirty_lines_and_no_more', () {
    final lines = linesToCheck(
      longScript(mostLinesForGroq),
      const NoSelection(),
      mostLines: mostLinesForGroq,
    );

    expect(lines, hasLength(mostLinesForGroq));
  });

  test('groq_rejects_thirty_one_lines', () {
    expect(
      () => linesToCheck(
        longScript(mostLinesForGroq + 1),
        const NoSelection(),
        mostLines: mostLinesForGroq,
      ),
      throwsA(isA<TooManyLinesForAiException>()),
    );
  });

  test('citation_marks_are_removed_from_the_reply_text', () {
    final corrected = applyCorrectedScript(
      script,
      '1 | 00:21.40 | 00:30.00 | درست ایک【1†L10-L12】',
    );

    expect(textsOf(corrected).first, 'درست ایک');
  });

  test('prompt_forbids_moving_lines_from_other_parts_of_the_poem', () {
    final prompt = scriptPromptFor(
      videoTitle: 'Some Naat',
      videoUrl: 'https://youtu.be/abc',
      lines: script.lines,
    );

    expect(prompt, contains('Never move a line from another part'));
  });

  test('prompt_keeps_row_numbers_of_the_full_script', () {
    final prompt = scriptPromptFor(
      videoTitle: 't',
      videoUrl: 'u',
      lines: longScript(225).lines.sublist(100, 102),
    );

    expect(prompt, contains('101 | 08:20.00 | 08:24.00 | line 100'));
  });
}
