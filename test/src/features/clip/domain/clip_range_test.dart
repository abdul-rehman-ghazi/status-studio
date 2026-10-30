import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const video = Duration(seconds: 60);

const transcript = Transcript(
  languageCode: 'en',
  lines: [
    TranscriptLine(
      index: 0,
      text: 'zero',
      start: Duration.zero,
      end: Duration(seconds: 9),
    ),
    TranscriptLine(
      index: 1,
      text: 'one',
      start: Duration(seconds: 10),
      end: Duration(seconds: 19),
    ),
    TranscriptLine(
      index: 2,
      text: 'two',
      start: Duration(seconds: 20),
      end: Duration(seconds: 29),
    ),
  ],
);

ClipRange clip(int startSeconds, int endSeconds) => ClipRange(
  start: Duration(seconds: startSeconds),
  end: Duration(seconds: endSeconds),
);

void main() {
  test('from_lines_spans_start_of_first_to_end_of_last', () {
    final range = ClipRange.fromLines(transcript, const RangeSelected(1, 2));

    expect(range, clip(10, 29));
  });

  test('length_is_end_minus_start', () {
    expect(clip(10, 29).length, const Duration(seconds: 19));
  });

  test('nudge_start_moves_by_delta', () {
    final nudged = clip(
      10,
      29,
    ).nudgeStart(-ClipRange.nudgeStep, videoDuration: video);

    expect(nudged.start, const Duration(milliseconds: 9500));
  });

  test('nudge_end_moves_by_delta', () {
    final nudged = clip(
      10,
      29,
    ).nudgeEnd(ClipRange.nudgeStep, videoDuration: video);

    expect(nudged.end, const Duration(milliseconds: 29500));
  });

  test('nudge_that_leaves_less_than_three_seconds_is_ignored', () {
    final nudged = clip(
      10,
      13,
    ).nudgeEnd(-ClipRange.nudgeStep, videoDuration: video);

    expect(nudged, clip(10, 13));
  });

  test('nudge_start_below_zero_is_ignored', () {
    final nudged = clip(
      0,
      10,
    ).nudgeStart(-ClipRange.nudgeStep, videoDuration: video);

    expect(nudged, clip(0, 10));
  });

  test('nudge_end_past_video_end_is_ignored', () {
    final nudged = clip(
      50,
      60,
    ).nudgeEnd(ClipRange.nudgeStep, videoDuration: video);

    expect(nudged, clip(50, 60));
  });

  test('nudge_that_lengthens_a_short_clip_is_applied', () {
    const short = ClipRange(
      start: Duration(seconds: 10),
      end: Duration(milliseconds: 11500),
    );

    final nudged = short.nudgeEnd(ClipRange.nudgeStep, videoDuration: video);

    expect(nudged.end, const Duration(seconds: 12));
  });

  test('nudge_start_allowed_when_clip_end_exceeds_video', () {
    final nudged = clip(
      50,
      62,
    ).nudgeStart(-ClipRange.nudgeStep, videoDuration: video);

    expect(nudged.start, const Duration(milliseconds: 49500));
  });

  test('nudge_end_inward_allowed_when_clip_end_exceeds_video', () {
    final nudged = clip(
      50,
      62,
    ).nudgeEnd(-ClipRange.nudgeStep, videoDuration: video);

    expect(nudged.end, const Duration(milliseconds: 61500));
  });
}
