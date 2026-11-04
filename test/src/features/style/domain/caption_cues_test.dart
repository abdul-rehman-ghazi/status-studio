import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/caption_cues.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

Duration seconds(int whole) => Duration(seconds: whole);

TranscriptLine line(int index, int startSecond, int endSecond) =>
    TranscriptLine(
      index: index,
      text: 'line $index',
      start: seconds(startSecond),
      end: seconds(endSecond),
    );

final spoken = [line(0, 10, 14), line(1, 14, 19), line(2, 20, 26)];
final clip = ClipRange(start: seconds(10), end: seconds(26));

void main() {
  test('cues_follow_spoken_times_when_line_counts_match', () {
    final cues = buildCaptionCues(
      captionText: 'one\ntwo\nthree',
      spokenLines: spoken,
      clip: clip,
    );

    expect(cues, [
      CaptionCue(text: 'one', start: seconds(0), end: seconds(4)),
      CaptionCue(text: 'two', start: seconds(4), end: seconds(9)),
      CaptionCue(text: 'three', start: seconds(10), end: seconds(16)),
    ]);
  });

  test('cues_are_clamped_to_a_nudged_clip', () {
    final nudged = ClipRange(start: seconds(12), end: seconds(24));

    final cues = buildCaptionCues(
      captionText: 'one\ntwo\nthree',
      spokenLines: spoken,
      clip: nudged,
    );

    expect(cues.map((cue) => (cue.start, cue.end)), [
      (seconds(0), seconds(2)),
      (seconds(2), seconds(7)),
      (seconds(8), seconds(12)),
    ]);
  });

  test('cue_outside_the_clip_is_dropped', () {
    final shortened = ClipRange(start: seconds(14), end: seconds(26));

    final cues = buildCaptionCues(
      captionText: 'one\ntwo\nthree',
      spokenLines: spoken,
      clip: shortened,
    );

    expect(cues.map((cue) => cue.text), ['two', 'three']);
  });

  test('edited_line_count_shares_the_clip_by_length', () {
    final cues = buildCaptionCues(
      captionText: 'abcd\nefghijklmnop',
      spokenLines: spoken,
      clip: clip,
    );

    expect(cues.map((cue) => (cue.start, cue.end)), [
      (seconds(0), seconds(4)),
      (seconds(4), seconds(16)),
    ]);
  });

  test('blank_lines_never_become_cues', () {
    final cues = buildCaptionCues(
      captionText: 'one\n\n  \ntwo',
      spokenLines: [spoken[0], spoken[1]],
      clip: clip,
    );

    expect(cues.map((cue) => cue.text), ['one', 'two']);
  });

  test('empty_caption_has_no_cues', () {
    final cues = buildCaptionCues(
      captionText: '  ',
      spokenLines: spoken,
      clip: clip,
    );

    expect(cues, isEmpty);
  });

  group('cueDueAt', () {
    const cues = [
      CaptionCue(
        text: 'a',
        start: Duration(seconds: 1),
        end: Duration(seconds: 3),
      ),
      CaptionCue(
        text: 'b',
        start: Duration(seconds: 3),
        end: Duration(seconds: 5),
      ),
    ];

    test('is_the_cue_playing_at_the_time', () {
      expect(cueDueAt(cues, const Duration(seconds: 2))?.text, 'a');
    });

    test('moves_on_at_a_cues_end', () {
      expect(cueDueAt(cues, const Duration(seconds: 3))?.text, 'b');
    });

    test('is_none_before_the_first_cue', () {
      expect(cueDueAt(cues, Duration.zero), isNull);
    });

    test('is_none_after_the_last_cue', () {
      expect(cueDueAt(cues, const Duration(seconds: 5)), isNull);
    });
  });
}
