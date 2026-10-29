import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
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
}
