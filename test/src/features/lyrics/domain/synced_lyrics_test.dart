import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/lyrics/domain/synced_lyrics.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const trackLength = Duration(minutes: 3, seconds: 30);

List<TranscriptLine> parse(String lrc) =>
    parseSyncedLyrics(lrc, trackLength: trackLength);

void main() {
  test('each_timed_row_becomes_a_line_ending_where_the_next_starts', () {
    final lines = parse(
      '[00:18.90] First\n[00:22.61] Second\n[00:26.00] Third',
    );

    expect(lines.map((line) => (line.text, line.start, line.end)).toList(), [
      (
        'First',
        const Duration(seconds: 18, milliseconds: 900),
        const Duration(seconds: 22, milliseconds: 610),
      ),
      (
        'Second',
        const Duration(seconds: 22, milliseconds: 610),
        const Duration(seconds: 26),
      ),
      ('Third', const Duration(seconds: 26), const Duration(seconds: 36)),
    ]);
  });

  test('empty_row_ends_the_line_before_it_and_is_not_a_line', () {
    final lines = parse('[00:10.00] Sung\n[00:13.00]\n[00:30.00] Later');

    expect(lines.map((line) => (line.text, line.end)).toList(), [
      ('Sung', const Duration(seconds: 13)),
      ('Later', const Duration(seconds: 40)),
    ]);
  });

  test('metadata_tags_are_ignored', () {
    final lines = parse('[ar:Rick Astley]\n[ti:Song]\n[00:05.00] Words');

    expect(lines.map((line) => line.text), ['Words']);
  });

  test('a_row_with_two_timestamps_repeats_the_line', () {
    final lines = parse('[00:05.00][01:05.00] Chorus\n[00:09.00] Verse');

    expect(lines.map((line) => line.text), ['Chorus', 'Verse', 'Chorus']);
  });

  test('lines_are_numbered_from_zero_in_time_order', () {
    final lines = parse('[00:09.00] Later\n[00:05.00] Earlier');

    expect(lines.map((line) => (line.index, line.text)), [
      (0, 'Earlier'),
      (1, 'Later'),
    ]);
  });

  test('last_line_ends_at_the_track_end_when_that_is_sooner', () {
    final lines = parseSyncedLyrics(
      '[00:58.00] Last',
      trackLength: const Duration(minutes: 1),
    );

    expect(lines.single.end, const Duration(minutes: 1));
  });

  test('plain_text_without_times_has_no_lines', () {
    expect(parse('Just words\nMore words'), isEmpty);
  });
}
