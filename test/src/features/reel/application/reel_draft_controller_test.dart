import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  late ProviderContainer container;
  late ReelDraftController controller;

  setUp(() {
    container = ProviderContainer.test();
    controller = container.read(reelDraftProvider.notifier);
  });

  ReelDraft draft() => container.read(reelDraftProvider);

  test('range_tap_sets_clip_from_lines', () {
    controller
      ..setTranscript(fixture)
      ..tapLine(1)
      ..tapLine(2);

    expect(
      draft().clip,
      ClipRange.fromLines(fixture, const RangeSelected(1, 2)),
    );
  });

  test('range_tap_fills_caption_with_selected_lines', () {
    controller
      ..setTranscript(fixture)
      ..tapLine(0)
      ..tapLine(1);

    expect(
      draft().caption.text,
      '${fixture.lines[0].text}\n${fixture.lines[1].text}',
    );
  });

  test('restarting_selection_clears_clip', () {
    controller
      ..setTranscript(fixture)
      ..tapLine(0)
      ..tapLine(1)
      ..tapLine(4);

    expect((draft().selection, draft().clip), (const StartSelected(4), null));
  });

  test('set_transcript_clears_selection_and_clip', () {
    controller
      ..setTranscript(fixture)
      ..tapLine(0)
      ..tapLine(1)
      ..setTranscript(fixture);

    expect((draft().selection, draft().clip), (const NoSelection(), null));
  });

  test('nudge_clip_start_moves_clip_start', () {
    controller
      ..setVideo(sampleVideo)
      ..setTranscript(fixture)
      ..tapLine(1)
      ..tapLine(3)
      ..nudgeClipStart(-ClipRange.nudgeStep);

    expect(draft().clip!.start, const Duration(milliseconds: 20900));
  });

  group('setting an edge at a video time', () {
    void pickLinesOneToThree() {
      controller
        ..setVideo(sampleVideo)
        ..setTranscript(fixture)
        ..tapLine(1)
        ..tapLine(3);
    }

    test('sets_the_clip_start', () {
      pickLinesOneToThree();

      controller.setClipStartAt(const Duration(seconds: 25));

      expect(draft().clip!.start, const Duration(seconds: 25));
    });

    test('sets_the_clip_end', () {
      pickLinesOneToThree();

      controller.setClipEndAt(const Duration(seconds: 45));

      expect(draft().clip!.end, const Duration(seconds: 45));
    });

    test('rounds_the_time_to_a_tenth_of_a_second', () {
      pickLinesOneToThree();

      controller.setClipStartAt(const Duration(milliseconds: 25049));

      expect(draft().clip!.start, const Duration(milliseconds: 25000));
    });

    test('ignores_a_start_that_would_leave_under_three_seconds', () {
      pickLinesOneToThree();

      controller.setClipStartAt(const Duration(seconds: 47));

      expect(draft().clip!.start, const Duration(milliseconds: 21400));
    });

    test('ignores_an_end_before_the_start', () {
      pickLinesOneToThree();

      controller.setClipEndAt(const Duration(seconds: 10));

      expect(draft().clip!.end, const Duration(milliseconds: 48800));
    });
  });

  test('start_new_resets_draft', () {
    controller
      ..setVideo(sampleVideo)
      ..startNew();

    expect(draft(), const ReelDraft());
  });

  group('editScript', () {
    void pickLinesOneToThree() {
      controller
        ..setVideo(sampleVideo)
        ..setTranscript(fixture)
        ..tapLine(1)
        ..tapLine(3);
    }

    test('keeps_the_clip_after_a_text_edit', () {
      pickLinesOneToThree();
      controller.nudgeClipStart(-ClipRange.nudgeStep);

      controller.editScript((script) => withLineText(script, 2, 'new'));

      expect(draft().clip!.start, const Duration(milliseconds: 20900));
    });

    test('refills_the_caption_from_the_edited_lines', () {
      pickLinesOneToThree();

      controller.editScript((script) => withLineText(script, 2, 'new'));

      expect(draft().caption.text.split('\n')[1], 'new');
    });

    test('keeps_the_range_on_the_same_lines_when_a_line_is_added_before', () {
      pickLinesOneToThree();

      controller.editScript(
        (script) => withLineAdded(
          script,
          text: 'new',
          playhead: const Duration(seconds: 13),
        ),
      );

      expect(draft().selection, const RangeSelected(2, 4));
    });

    test('keeps_a_nudged_clip_when_a_line_is_added_before_the_range', () {
      pickLinesOneToThree();
      controller.nudgeClipStart(-ClipRange.nudgeStep);

      controller.editScript(
        (script) => withLineAdded(
          script,
          text: 'new',
          playhead: const Duration(seconds: 13),
        ),
      );

      expect(draft().clip!.start, const Duration(milliseconds: 20900));
    });

    test('moves_the_clip_start_when_its_first_line_is_timed', () {
      pickLinesOneToThree();

      controller.editScript(
        (script) => withLineTimedAt(script, 1, const Duration(seconds: 23)),
      );

      expect(draft().clip!.start, const Duration(seconds: 23));
    });

    test('keeps_a_nudge_of_the_other_edge_when_one_edge_is_timed', () {
      pickLinesOneToThree();
      controller.nudgeClipEnd(ClipRange.nudgeStep);

      controller.editScript(
        (script) => withLineTimedAt(script, 1, const Duration(seconds: 23)),
      );

      expect(draft().clip!.end, const Duration(milliseconds: 49300));
    });

    test('ignores_lines_still_being_written_after_an_edit', () {
      pickLinesOneToThree();
      controller.editScript((script) => withLineText(script, 2, 'new'));

      controller.growTranscript(
        fixture.copyWith(lines: [...fixture.lines, fixture.lines.last]),
      );

      expect(draft().transcript!.lines[2].text, 'new');
    });

    test('fails_when_no_lines_are_picked', () {
      controller
        ..setVideo(sampleVideo)
        ..setTranscript(fixture);

      expect(() => controller.editScript((script) => script), throwsStateError);
    });
  });

  group('moving crop', () {
    const centre = CropAnchor(x: 0.5, y: 0.5);
    const farRight = CropAnchor(x: 1, y: 0.5);

    void pickLinesOneToThree() {
      controller
        ..setVideo(sampleVideo)
        ..setTranscript(fixture)
        ..tapLine(1)
        ..tapLine(3);
    }

    Duration clipStart() => draft().clip!.start;

    test('starting_makes_a_keyframe_at_the_clip_start_from_the_crop', () {
      pickLinesOneToThree();

      controller.startMovingCrop();

      expect(draft().frame.cropPath.keyframes.single.time, clipStart());
    });

    test('the_first_keyframe_has_the_fixed_crops_anchor', () {
      pickLinesOneToThree();
      controller.updateFrame(draft().frame.withFocus(CropFocus.right));

      controller.startMovingCrop();

      expect(draft().frame.cropPath.keyframes.single.anchor.x, 1);
    });

    test('a_keyframe_before_the_clip_is_set_at_the_clip_start', () {
      pickLinesOneToThree();
      controller.startMovingCrop();

      controller.moveCropTo(clipStart() - const Duration(seconds: 3), farRight);

      expect(draft().frame.cropPath.keyframes.single.anchor, farRight);
    });

    test('a_keyframe_after_the_clip_is_set_at_the_clip_end', () {
      pickLinesOneToThree();
      controller.startMovingCrop();

      controller.moveCropTo(
        draft().clip!.end + const Duration(seconds: 3),
        farRight,
      );

      expect(draft().frame.cropPath.keyframes.last.time, draft().clip!.end);
    });

    test('stopping_keeps_the_crop_as_it_was_at_the_clip_start_for_fill', () {
      pickLinesOneToThree();
      controller
        ..startMovingCrop()
        ..moveCropTo(clipStart(), farRight)
        ..stopMovingCrop();

      expect(
        (draft().frame.cropPath.isEmpty, draft().frame.anchor),
        (true, farRight),
      );
    });

    test('stopping_writes_the_start_position_into_a_free_crop', () {
      pickLinesOneToThree();
      controller
        ..updateFrame(const FrameSettings(preset: AspectPreset.free))
        ..startMovingCrop()
        ..moveCropTo(clipStart(), farRight)
        ..stopMovingCrop();

      expect(draft().frame.freeCrop.left, closeTo(0.6, 1e-9));
    });

    test('an_arrival_can_be_changed_and_a_keyframe_removed', () {
      pickLinesOneToThree();
      controller
        ..startMovingCrop()
        ..moveCropTo(clipStart() + const Duration(seconds: 5), centre)
        ..setCropArrival(1, CropArrival.cut);

      expect(draft().frame.cropPath.keyframes[1].arrival, CropArrival.cut);
    });

    test('removing_a_keyframe_drops_it', () {
      pickLinesOneToThree();
      controller
        ..startMovingCrop()
        ..moveCropTo(clipStart() + const Duration(seconds: 5), centre)
        ..removeCropKeyframe(1);

      expect(draft().frame.cropPath.keyframes.length, 1);
    });

    test('picking_other_lines_stops_the_moving_crop', () {
      pickLinesOneToThree();
      controller
        ..startMovingCrop()
        ..moveCropTo(clipStart(), farRight)
        ..tapLine(2);

      expect(
        (draft().frame.cropPath.isEmpty, draft().frame.anchor),
        (true, farRight),
      );
    });

    test('a_new_script_stops_the_moving_crop', () {
      pickLinesOneToThree();
      controller
        ..startMovingCrop()
        ..setTranscript(fixture);

      expect(draft().frame.cropPath.isEmpty, isTrue);
    });

    test('a_followed_path_replaces_the_keyframes', () {
      pickLinesOneToThree();
      controller
        ..startMovingCrop()
        ..moveCropTo(clipStart() + const Duration(seconds: 5), centre);
      final followed = CropPath([
        CropKeyframe(
          time: clipStart(),
          anchor: farRight,
          arrival: CropArrival.glide,
        ),
      ]);

      controller.followCrop(followed);

      expect(draft().frame.cropPath, followed);
    });

    test('a_followed_path_leaves_the_rest_of_the_frame_alone', () {
      pickLinesOneToThree();
      controller.startMovingCrop();
      final before = draft().frame;

      controller.followCrop(
        CropPath.startingAt(clipStart(), const CropAnchor(x: 0, y: 0.5)),
      );

      expect(draft().frame.anchor, before.anchor);
      expect(draft().frame.preset, before.preset);
    });

    test('a_followed_path_cannot_be_empty', () {
      pickLinesOneToThree();
      controller.startMovingCrop();

      expect(
        () => controller.followCrop(const CropPath()),
        throwsArgumentError,
      );
    });

    test('starting_without_a_clip_fails', () {
      expect(() => controller.startMovingCrop(), throwsStateError);
    });
  });
}
