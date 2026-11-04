import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft_json.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

FineTuneDraft _draft() => FineTuneDraft(
  script: const TranscriptKey(
    videoId: 's6kE_uP3xH4',
    language: ScriptLanguage.urdu,
  ),
  selection: const RangeSelected(12, 19),
  clip: const ClipRange(
    start: Duration(milliseconds: 61234),
    end: Duration(milliseconds: 84701),
  ),
  frame: const FrameSettings(
    preset: AspectPreset.free,
    anchor: CropAnchor(x: 0.25, y: 0.75),
    freeCrop: FreeCropRect(left: 0.1, top: 0.05, width: 0.5, height: 0.9),
    cropPath: CropPath([
      CropKeyframe(
        time: Duration(milliseconds: 61300),
        anchor: CropAnchor(x: 0.3, y: 0.5),
        arrival: CropArrival.glide,
      ),
      CropKeyframe(
        time: Duration(milliseconds: 70100),
        anchor: CropAnchor(x: 0.9, y: 0.5),
        arrival: CropArrival.cut,
      ),
    ]),
  ),
  caption: const CaptionSettings(
    variant: CaptionVariant.roman,
    text: 'ab kya kare\nhum',
    position: CaptionPosition.top,
    size: CaptionSize.large,
  ),
  linesEdited: true,
  scriptFingerprint: 2166136261,
  savedAt: DateTime.utc(2026, 11, 4, 10, 15, 0, 123),
);

Map<String, Object?> _json() =>
    jsonDecode(jsonEncode(fineTuneDraftToJson(_draft())))
        as Map<String, Object?>;

Map<String, Object?> _section(Map<String, Object?> json, String name) =>
    json[name]! as Map<String, Object?>;

void main() {
  test('a_draft_round_trips_through_json', () {
    final restored = fineTuneDraftFromJson(_json());

    expect(restored, _draft());
  });

  test('times_are_kept_to_the_millisecond', () {
    final restored = fineTuneDraftFromJson(_json());

    expect(restored.clip.start, const Duration(milliseconds: 61234));
    expect(restored.savedAt, DateTime.utc(2026, 11, 4, 10, 15, 0, 123));
  });

  test('json_carries_version_1', () {
    expect(_json()['version'], 1);
  });

  test('a_newer_version_is_rejected', () {
    final json = _json()..['version'] = 2;

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('a_missing_field_is_rejected', () {
    final json = _json()..remove('clip');

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('an_unknown_enum_name_is_rejected', () {
    final json = _json();
    _section(json, 'frame')['preset'] = 'cinema';

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('an_unknown_language_code_is_rejected', () {
    final json = _json()..['language'] = 'xx';

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('keyframes_out_of_time_order_are_rejected', () {
    final json = _json();
    final keyframes = _section(json, 'frame')['keyframes']! as List<Object?>;
    final reordered = keyframes.reversed.toList();
    _section(json, 'frame')['keyframes'] = reordered;

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('an_anchor_outside_0_to_1_is_rejected', () {
    final json = _json();
    _section(_section(json, 'frame'), 'anchor')['x'] = 1.5;

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('a_free_crop_outside_the_frame_is_rejected', () {
    final json = _json();
    _section(_section(json, 'frame'), 'freeCrop')['left'] = 0.8;

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('a_reversed_range_is_rejected', () {
    final json = _json();
    _section(json, 'selection')
      ..['start'] = 9
      ..['end'] = 3;

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('a_clip_ending_before_it_starts_is_rejected', () {
    final json = _json();
    _section(json, 'clip')
      ..['startMs'] = 9000
      ..['endMs'] = 8000;

    expect(() => fineTuneDraftFromJson(json), throwsFormatException);
  });

  test('whole_numbers_are_read_as_doubles', () {
    final json = _json();
    _section(_section(json, 'frame'), 'anchor')
      ..['x'] = 1
      ..['y'] = 0;

    final restored = fineTuneDraftFromJson(json);

    expect(restored.frame.anchor, const CropAnchor(x: 1, y: 0));
  });

  test('unknown_extra_fields_are_ignored', () {
    final json = _json()..['addedLater'] = 'ok';

    expect(fineTuneDraftFromJson(json), _draft());
  });
}
