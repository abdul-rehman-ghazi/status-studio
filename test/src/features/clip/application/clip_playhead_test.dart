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
}
