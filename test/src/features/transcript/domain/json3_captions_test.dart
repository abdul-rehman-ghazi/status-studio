import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/domain/caption_track_choice.dart';
import 'package:status_studio/src/features/transcript/domain/json3_captions.dart';

void main() {
  test('json3_events_become_cues', () {
    final cues = captionsFromJson3({
      'events': [
        {
          'tStartMs': 18640,
          'dDurationMs': 3240,
          'segs': [
            {'utf8': "We're no "},
            {'utf8': 'strangers'},
          ],
        },
      ],
    });

    expect(cues, const [
      CaptionCue(
        text: "We're no strangers",
        start: Duration(milliseconds: 18640),
        end: Duration(milliseconds: 21880),
      ),
    ]);
  });

  test('json3_events_without_text_are_skipped', () {
    final cues = captionsFromJson3({
      'events': [
        {'tStartMs': 0, 'dDurationMs': 548000, 'id': 1, 'wpWinPosId': 1},
        {
          'tStartMs': 1000,
          'dDurationMs': 500,
          'segs': [
            {'utf8': 'words'},
          ],
        },
      ],
    });

    expect(cues.map((cue) => cue.text), ['words']);
  });
}
