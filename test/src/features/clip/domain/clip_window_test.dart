import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';

const video = Duration(minutes: 6, seconds: 48);

ClipRange clip(Duration start, Duration end) =>
    ClipRange(start: start, end: end);

Duration at(int minutes, int seconds) =>
    Duration(minutes: minutes, seconds: seconds);

void main() {
  test('window_pads_five_seconds_each_side', () {
    final window = clipWindowFor(clip(at(1, 0), at(1, 40)), video);

    expect(window, ClipWindow(start: at(0, 55), end: at(1, 45)));
  });

  test('window_is_at_least_thirty_seconds', () {
    final window = clipWindowFor(clip(at(1, 0), at(1, 5)), video);

    expect(window, ClipWindow(start: at(0, 55), end: at(1, 30)));
  });

  test('window_clamped_at_video_start', () {
    final window = clipWindowFor(clip(at(0, 2), at(0, 40)), video);

    expect(window.start, Duration.zero);
  });

  test('window_clamped_at_video_end', () {
    final window = clipWindowFor(clip(at(6, 30), at(6, 46)), video);

    expect(window.end, video);
  });

  test('covers_clip_inside_window', () {
    final window = ClipWindow(start: at(0, 55), end: at(1, 45));

    expect(window.covers(clip(at(1, 0), at(1, 40))), isTrue);
  });

  test('does_not_cover_clip_that_leaves_window', () {
    final window = ClipWindow(start: at(0, 55), end: at(1, 45));

    expect(window.covers(clip(at(1, 0), at(1, 46))), isFalse);
  });
}
