import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';

SpeechSegment segment(int fromSeconds, int toSeconds, String text) =>
    SpeechSegment(
      from: Duration(seconds: fromSeconds),
      to: Duration(seconds: toSeconds),
      text: text,
    );

void main() {
  test('offsets_segment_times_by_chunk_start', () {
    final lines = linesFromSegments(
      [segment(3, 7, 'hello')],
      offset: const Duration(seconds: 90),
      firstIndex: 0,
    );

    expect(
      (lines.single.start, lines.single.end),
      (const Duration(seconds: 93), const Duration(seconds: 97)),
    );
  });

  test('numbers_lines_from_first_index', () {
    final lines = linesFromSegments(
      [segment(0, 1, 'a'), segment(1, 2, 'b')],
      offset: Duration.zero,
      firstIndex: 5,
    );

    expect(lines.map((line) => line.index), [5, 6]);
  });

  test('drops_non_speech_segments', () {
    final lines = linesFromSegments(
      [
        segment(0, 1, ' [BLANK_AUDIO] '),
        segment(1, 2, '(music)'),
        segment(2, 3, '♪ ♪'),
        segment(3, 4, '   '),
        segment(4, 5, 'real words'),
      ],
      offset: Duration.zero,
      firstIndex: 0,
    );

    expect(lines.map((line) => line.text), ['real words']);
  });

  test('drops_numbering_gaps_left_by_dropped_segments', () {
    final lines = linesFromSegments(
      [segment(0, 1, '[Music]'), segment(1, 2, 'words')],
      offset: Duration.zero,
      firstIndex: 0,
    );

    expect(lines.single.index, 0);
  });

  test('trims_whitespace', () {
    final lines = linesFromSegments(
      [segment(0, 1, '  spaced out \n')],
      offset: Duration.zero,
      firstIndex: 0,
    );

    expect(lines.single.text, 'spaced out');
  });
}
