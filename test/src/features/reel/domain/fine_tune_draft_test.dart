import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const _video = SourceVideo(
  videoId: 'abc123',
  title: 'A song',
  channel: 'A channel',
  duration: Duration(seconds: 60),
);

final _savedAt = DateTime.utc(2026, 11, 4, 10);

Transcript _script({List<String> texts = const []}) {
  const defaults = ['ek', 'do', 'teen', 'char', 'paanch'];
  final words = texts.isEmpty ? defaults : texts;
  return Transcript(
    languageCode: 'ur',
    lines: [
      for (var index = 0; index < words.length; index++)
        TranscriptLine(
          index: index,
          text: words[index],
          start: Duration(seconds: index * 2),
          end: Duration(seconds: index * 2 + 2),
        ),
    ],
  );
}

ReelDraft _pickedDraft({Transcript? transcript}) {
  return ReelDraft(
    video: _video,
    language: ScriptLanguage.urdu,
    transcript: transcript ?? _script(),
  ).withSelection(const RangeSelected(1, 3));
}

FineTuneDraft _kept([ReelDraft? draft]) =>
    FineTuneDraft.of(draft ?? _pickedDraft(), savedAt: _savedAt);

void main() {
  test('a_draft_with_a_range_and_clip_can_be_kept', () {
    expect(FineTuneDraft.canKeep(_pickedDraft()), isTrue);
  });

  test('a_draft_without_a_range_cannot_be_kept', () {
    final draft = ReelDraft(
      video: _video,
      language: ScriptLanguage.urdu,
      transcript: _script(),
    );

    expect(FineTuneDraft.canKeep(draft), isFalse);
  });

  test('restoring_gives_back_the_same_reel_draft', () {
    final original = _pickedDraft().copyWith(
      frame: const FrameSettings(preset: AspectPreset.square1x1),
      linesEdited: true,
    );

    final restored = _kept(original).restoredOnto(_video, _script());

    expect(restored, original);
  });

  test('the_same_script_fits', () {
    expect(_kept().fits(_video, _script()), isTrue);
  });

  test('a_script_with_lines_added_after_the_range_still_fits', () {
    final grown = _script(
      texts: ['ek', 'do', 'teen', 'char', 'paanch', 'chhe'],
    );

    expect(_kept().fits(_video, grown), isTrue);
  });

  test('a_changed_line_inside_the_range_does_not_fit', () {
    final changed = _script(texts: ['ek', 'do', 'TEEN', 'char', 'paanch']);

    expect(_kept().fits(_video, changed), isFalse);
  });

  test('a_changed_line_before_the_range_does_not_fit', () {
    final changed = _script(texts: ['EK', 'do', 'teen', 'char', 'paanch']);

    expect(_kept().fits(_video, changed), isFalse);
  });

  test('a_range_past_the_script_end_does_not_fit', () {
    final shorter = _script(texts: ['ek', 'do', 'teen']);

    expect(_kept().fits(_video, shorter), isFalse);
  });

  test('a_clip_past_the_video_end_does_not_fit', () {
    const shortVideo = SourceVideo(
      videoId: 'abc123',
      title: 'A song',
      channel: 'A channel',
      duration: Duration(seconds: 7),
    );

    expect(_kept().fits(shortVideo, _script()), isFalse);
  });

  test('the_fingerprint_is_the_same_across_runs', () {
    expect(_kept().scriptFingerprint, 331970932);
  });

  test('starting_over_keeps_size_fill_and_caption_position_and_size', () {
    final original = _pickedDraft().copyWith(
      frame: const FrameSettings(
        preset: AspectPreset.portrait4x5,
        fill: FillMode.blur,
      ),
      caption: const CaptionSettings(
        position: CaptionPosition.top,
        size: CaptionSize.large,
      ),
    );

    final started = _kept(original).startOver(_video);

    expect(started.frame.preset, AspectPreset.portrait4x5);
    expect(started.frame.fill, FillMode.blur);
    expect(started.caption.position, CaptionPosition.top);
    expect(started.caption.size, CaptionSize.large);
  });

  test(
    'starting_over_keeps_the_moving_crop_where_it_was_at_the_clip_start',
    () {
      final moving = _pickedDraft()
          .withMovingCropStarted()
          .withCropAnchorAt(
            const Duration(seconds: 2),
            const CropAnchor(x: 0.2, y: 0.5),
          )
          .withCropAnchorAt(
            const Duration(seconds: 6),
            const CropAnchor(x: 0.9, y: 0.5),
          );

      final started = _kept(moving).startOver(_video);

      expect(started.frame.cropPath.isEmpty, isTrue);
      expect(started.frame.anchor, const CropAnchor(x: 0.2, y: 0.5));
    },
  );

  test('starting_over_drops_lines_clip_and_caption_text', () {
    final started = _kept().startOver(_video);

    expect(started.transcript, isNull);
    expect(started.selection, const NoSelection());
    expect(started.clip, isNull);
    expect(started.caption.text, isEmpty);
  });

  test('starting_over_names_the_video_and_requested_language', () {
    final started = _kept().startOver(_video);

    expect(started.video, _video);
    expect(started.language, ScriptLanguage.urdu);
  });

  test('a_clip_range_survives_keeping', () {
    expect(
      _kept().clip,
      const ClipRange(start: Duration(seconds: 2), end: Duration(seconds: 8)),
    );
  });
}
