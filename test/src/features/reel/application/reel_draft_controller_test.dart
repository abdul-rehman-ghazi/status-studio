import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
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

    test('widens_the_clip_when_a_line_after_the_range_joins_it', () {
      pickLinesOneToThree();

      controller.editScript(
        (script) => withLineTimedAt(script, 4, const Duration(seconds: 50)),
      );

      expect(draft().clip!.end, const Duration(milliseconds: 58600));
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
}
