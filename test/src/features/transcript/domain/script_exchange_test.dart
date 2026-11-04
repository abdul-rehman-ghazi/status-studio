import 'package:flutter_test/flutter_test.dart';
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
      transcript: script,
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
}
