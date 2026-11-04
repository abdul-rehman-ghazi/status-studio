import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';

void main() {
  var now = Duration.zero;
  late ClipPlayhead playhead;

  setUp(() {
    now = Duration.zero;
    playhead = ClipPlayhead(clock: () => now);
  });

  test('position_advances_between_reports_while_playing', () {
    playhead.report(position: const Duration(seconds: 10), isPlaying: true);

    now += const Duration(milliseconds: 300);

    expect(playhead.position, const Duration(milliseconds: 10300));
  });

  test('position_holds_while_paused', () {
    playhead.report(position: const Duration(seconds: 10), isPlaying: false);

    now += const Duration(seconds: 3);

    expect(playhead.position, const Duration(seconds: 10));
  });

  test('seek_goes_to_the_attached_player', () async {
    Duration? sought;
    playhead.attach((videoTime) async => sought = videoTime);

    await playhead.seekTo(const Duration(seconds: 7));

    expect(sought, const Duration(seconds: 7));
  });

  test('seek_without_a_player_fails', () {
    expect(() => playhead.seekTo(const Duration(seconds: 7)), throwsStateError);
  });

  test('is_not_ready_after_the_player_detaches', () {
    playhead
      ..attach((videoTime) async {})
      ..detach();

    expect(playhead.isReady, isFalse);
  });

  test('is_not_playing_after_the_player_detaches', () {
    playhead
      ..attach((videoTime) async {})
      ..report(position: Duration.zero, isPlaying: true)
      ..detach();

    expect(playhead.isPlaying, isFalse);
  });

  group('a report while playing', () {
    test('a_small_correction_is_blended_in_not_jumped_to', () {
      playhead.report(position: const Duration(seconds: 10), isPlaying: true);
      now += const Duration(milliseconds: 300);

      playhead.report(
        position: const Duration(milliseconds: 10200),
        isPlaying: true,
      );

      // 10.3 s was shown; a jump back to 10.2 s would be seen as a stutter.
      expect(playhead.position.inMilliseconds, inInclusiveRange(10250, 10300));
    });

    test('a_forward_correction_is_blended_in_too', () {
      playhead.report(position: const Duration(seconds: 10), isPlaying: true);
      now += const Duration(milliseconds: 300);

      playhead.report(
        position: const Duration(milliseconds: 10400),
        isPlaying: true,
      );

      expect(playhead.position.inMilliseconds, inInclusiveRange(10300, 10350));
    });

    test('a_big_difference_is_a_seek_and_is_followed_at_once', () {
      playhead.report(position: const Duration(seconds: 10), isPlaying: true);
      now += const Duration(milliseconds: 300);

      playhead.report(position: const Duration(seconds: 30), isPlaying: true);

      expect(playhead.position, const Duration(seconds: 30));
    });

    test('the_first_report_after_a_pause_is_taken_as_it_is', () {
      playhead.report(position: const Duration(seconds: 10), isPlaying: false);
      now += const Duration(seconds: 5);

      playhead.report(
        position: const Duration(milliseconds: 10100),
        isPlaying: true,
      );

      expect(playhead.position, const Duration(milliseconds: 10100));
    });
  });
}
