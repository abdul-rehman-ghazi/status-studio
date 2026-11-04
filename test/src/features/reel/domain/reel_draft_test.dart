import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  final firstTwoLines = fixture.copyWith(lines: fixture.lines.sublist(0, 2));

  test('growing_transcript_keeps_selection_and_clip', () {
    final picked = const ReelDraft()
        .withTranscript(firstTwoLines)
        .withSelection(const RangeSelected(0, 1));

    final grown = picked.withGrowingTranscript(fixture);

    expect(
      (grown.selection, grown.clip, grown.transcript),
      (picked.selection, picked.clip, fixture),
    );
  });

  test('different_transcript_clears_selection', () {
    final picked = const ReelDraft()
        .withTranscript(fixture)
        .withSelection(const RangeSelected(0, 1));
    const other = Transcript(languageCode: 'en', lines: []);

    final replaced = picked.withGrowingTranscript(other);

    expect(replaced.selection, const NoSelection());
  });

  Transcript corrected() => fixture.copyWith(
    lines: [
      for (final line in fixture.lines)
        line.copyWith(text: 'fixed ${line.index}'),
    ],
  );

  test('corrected_lines_keep_the_picked_range_and_clip', () {
    final fixed = pickedDraft.withCorrectedLines(corrected());

    expect(
      (fixed.selection, fixed.clip),
      (pickedDraft.selection, pickedDraft.clip),
    );
  });

  test('corrected_lines_refill_the_caption', () {
    final fixed = pickedDraft.withCorrectedLines(corrected());

    expect(fixed.caption.text, 'fixed 1\nfixed 2\nfixed 3');
  });

  test('corrected_lines_without_a_pick_only_swap_the_transcript', () {
    final fixed = scriptDraft.withCorrectedLines(corrected());

    expect(
      (fixed.transcript, fixed.selection),
      (corrected(), scriptDraft.selection),
    );
  });
}
