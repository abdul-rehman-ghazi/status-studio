import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_playback.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';

const clip = ClipRange(
  start: Duration(seconds: 10),
  end: Duration(seconds: 20),
);

void main() {
  test('stops_at_clip_end', () {
    expect(shouldStopPlayback(const Duration(seconds: 20), clip), isTrue);
  });

  test('keeps_playing_before_clip_end', () {
    expect(
      shouldStopPlayback(const Duration(milliseconds: 19900), clip),
      isFalse,
    );
  });
}
