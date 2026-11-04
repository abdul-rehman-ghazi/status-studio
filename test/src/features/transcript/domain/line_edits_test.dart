import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

Duration seconds(int value) => Duration(seconds: value);

TranscriptLine lineAt(int index, String text) => TranscriptLine(
  index: index,
  text: text,
  start: seconds(index * 4),
  end: seconds(index * 4 + 4),
);

/// Five lines "a".."e", four seconds each; lines 1–3 picked.
PickedScript scriptOfFive({
  RangeSelected selection = const RangeSelected(1, 3),
}) {
  return PickedScript(
    transcript: Transcript(
      languageCode: 'ur',
      lines: [
        for (final (index, text) in ['a', 'b', 'c', 'd', 'e'].indexed)
          lineAt(index, text),
      ],
    ),
    selection: selection,
  );
}

List<String> texts(PickedScript script) =>
    script.transcript.lines.map((line) => line.text).toList();

void main() {
  group('withLineText', () {
    test('replaces_the_text_and_keeps_the_times', () {
      final edited = withLineText(scriptOfFive(), 2, 'new');

      expect(edited.transcript.lines[2], lineAt(2, 'new'));
    });

    test('turns_a_line_break_into_a_space', () {
      final edited = withLineText(scriptOfFive(), 2, 'one\ntwo');

      expect(edited.transcript.lines[2].text, 'one two');
    });

    test('keeps_the_old_text_when_the_new_one_is_blank', () {
      final script = scriptOfFive();

      expect(withLineText(script, 2, '   '), script);
    });
  });

  group('withLineTextMoved', () {
    test('moves_the_text_down_and_leaves_times_in_place', () {
      final moved = withLineTextMoved(scriptOfFive(), 1, 3);

      expect(texts(moved), ['a', 'c', 'd', 'b', 'e']);
      expect(moved.transcript.lines[3].start, seconds(12));
    });

    test('moves_the_text_up', () {
      expect(texts(withLineTextMoved(scriptOfFive(), 3, 1)), [
        'a',
        'd',
        'b',
        'c',
        'e',
      ]);
    });
  });

  group('withLineAdded', () {
    test('inserts_at_the_playhead_in_time_order', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(9),
      );

      expect(texts(added), ['a', 'b', 'c', 'x', 'd', 'e']);
      expect(added.transcript.lines[3].index, 3);
    });

    test('ends_the_line_it_lands_in_at_the_playhead', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(9),
      );

      expect(added.transcript.lines[2].end, seconds(9));
    });

    test('lasts_two_seconds_and_stops_at_the_next_line', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(11),
      );

      expect(added.transcript.lines[3].end, seconds(12));
    });

    test('lasts_two_seconds_when_nothing_follows', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(21),
      );

      expect(added.transcript.lines.last.end, seconds(23));
    });

    test('inside_the_range_it_joins_the_range', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(9),
      );

      expect(added.selection, const RangeSelected(1, 4));
    });

    test('before_the_range_it_shifts_the_range', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(1),
      );

      expect(added.selection, const RangeSelected(2, 4));
    });

    test('after_the_range_it_leaves_the_range', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(17),
      );

      expect(added.selection, const RangeSelected(1, 3));
    });

    test('a_blank_text_adds_nothing', () {
      final script = scriptOfFive();

      expect(withLineAdded(script, text: ' ', playhead: seconds(9)), script);
    });
  });

  group('withLineAdded at a line start or inside the last picked line', () {
    test('at_a_lines_start_splits_that_lines_time', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(8),
      );

      expect(
        [
          for (final line in added.transcript.lines.sublist(2, 4))
            (line.text, line.start, line.end),
        ],
        [('x', seconds(8), seconds(10)), ('c', seconds(10), seconds(12))],
      );
    });

    test('at_the_start_of_a_short_line_takes_half_of_it', () {
      final base = scriptOfFive();
      final shortLine = base.transcript.lines[2].copyWith(end: seconds(9));
      final script = PickedScript(
        transcript: base.transcript.copyWith(
          lines: [...base.transcript.lines]..[2] = shortLine,
        ),
        selection: base.selection,
      );

      final added = withLineAdded(script, text: 'x', playhead: seconds(8));

      expect(added.transcript.lines[2].end, const Duration(milliseconds: 8500));
    });

    test('at_the_first_picked_lines_start_it_joins_the_range', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(4),
      );

      expect(added.selection, const RangeSelected(1, 4));
    });

    test('inside_the_last_picked_line_it_joins_the_range', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x',
        playhead: seconds(13),
      );

      expect(added.selection, const RangeSelected(1, 4));
    });

    test('a_line_break_in_the_text_becomes_a_space', () {
      final added = withLineAdded(
        scriptOfFive(),
        text: 'x\ny',
        playhead: seconds(9),
      );

      expect(added.transcript.lines[3].text, 'x y');
    });
  });

  group('withLineRemoved', () {
    test('removes_the_line_and_renumbers', () {
      final removed = withLineRemoved(scriptOfFive(), 2);

      expect(texts(removed), ['a', 'b', 'd', 'e']);
      expect(removed.transcript.lines[2].index, 2);
    });

    test('inside_the_range_shrinks_it', () {
      expect(
        withLineRemoved(scriptOfFive(), 2).selection,
        const RangeSelected(1, 2),
      );
    });

    test('before_the_range_shifts_it', () {
      expect(
        withLineRemoved(scriptOfFive(), 0).selection,
        const RangeSelected(0, 2),
      );
    });

    test('after_the_range_leaves_it', () {
      expect(
        withLineRemoved(scriptOfFive(), 4).selection,
        const RangeSelected(1, 3),
      );
    });

    test('rejects_the_last_picked_line', () {
      final script = scriptOfFive(selection: const RangeSelected(2, 2));

      expect(() => withLineRemoved(script, 2), throwsStateError);
    });
  });

  group('withLineTimedAt', () {
    test('starts_the_line_at_the_playhead', () {
      final timed = withLineTimedAt(scriptOfFive(), 2, seconds(9));

      expect(timed.transcript.lines[2].start, seconds(9));
    });

    test('keeps_the_lines_length', () {
      final timed = withLineTimedAt(scriptOfFive(), 4, seconds(17));

      expect(timed.transcript.lines[4].end, seconds(21));
    });

    test('gives_a_line_at_least_one_second', () {
      final base = scriptOfFive();
      final shortened = PickedScript(
        transcript: base.transcript.copyWith(
          lines: [
            for (final line in base.transcript.lines)
              line.index == 2
                  ? line.copyWith(
                      end: line.start + const Duration(milliseconds: 500),
                    )
                  : line,
          ],
        ),
        selection: base.selection,
      );

      final timed = withLineTimedAt(shortened, 2, seconds(10));

      expect(timed.transcript.lines[2].end, seconds(11));
    });

    test('cuts_the_line_at_the_next_lines_start', () {
      final timed = withLineTimedAt(scriptOfFive(), 1, seconds(7));

      expect(timed.transcript.lines[1].end, seconds(8));
    });

    test('ends_the_line_that_was_highlighted', () {
      final timed = withLineTimedAt(scriptOfFive(), 2, seconds(6));

      expect(timed.transcript.lines[1].end, seconds(6));
    });

    test('ignores_a_tap_on_an_earlier_line_than_the_one_playing', () {
      final script = scriptOfFive();

      expect(withLineTimedAt(script, 2, seconds(14)), script);
    });

    test('ignores_a_tap_before_the_previous_lines_start', () {
      final script = scriptOfFive();

      expect(withLineTimedAt(script, 2, seconds(3)), script);
    });

    test('a_tapped_line_outside_the_range_extends_it_to_include_it', () {
      final timed = withLineTimedAt(scriptOfFive(), 4, seconds(17));

      expect(timed.selection, const RangeSelected(1, 4));
    });

    test('a_tapped_line_before_the_range_extends_it_to_include_it', () {
      final timed = withLineTimedAt(scriptOfFive(), 0, seconds(1));

      expect(timed.selection, const RangeSelected(0, 3));
    });
  });

  group('highlightedLineIndex', () {
    final lines = scriptOfFive().transcript.lines;

    test('is_the_line_playing_at_the_position', () {
      expect(highlightedLineIndex(lines, seconds(9)), 2);
    });

    test('moves_on_at_a_lines_end', () {
      expect(highlightedLineIndex(lines, seconds(8)), 2);
    });

    test('is_none_after_the_last_line', () {
      expect(highlightedLineIndex(lines, seconds(20)), isNull);
    });

    test('is_none_in_a_gap_between_lines', () {
      final gapped = [lines[0].copyWith(end: seconds(2)), lines[1]];

      expect(highlightedLineIndex(gapped, seconds(3)), isNull);
    });
  });
}
