import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';

void main() {
  test('first_tap_selects_start', () {
    expect(const NoSelection().tap(3), const StartSelected(3));
  });

  test('tap_after_start_selects_range', () {
    expect(const StartSelected(3).tap(5), const RangeSelected(3, 5));
  });

  test('tap_on_start_selects_single_line_range', () {
    expect(const StartSelected(3).tap(3), const RangeSelected(3, 3));
  });

  test('tap_before_start_restarts_selection', () {
    expect(const StartSelected(3).tap(1), const StartSelected(1));
  });

  test('tap_after_range_restarts_selection', () {
    expect(const RangeSelected(3, 5).tap(7), const StartSelected(7));
  });

  test('range_highlights_lines_between_start_and_end', () {
    const selection = RangeSelected(3, 5);

    final highlighted = [2, 3, 4, 5, 6].map(selection.isHighlighted);

    expect(highlighted, [false, true, true, true, false]);
  });

  test('start_highlights_only_the_start_line', () {
    const selection = StartSelected(3);

    final highlighted = [2, 3, 4].map(selection.isHighlighted);

    expect(highlighted, [false, true, false]);
  });

  test('no_selection_highlights_nothing', () {
    expect(const NoSelection().isHighlighted(0), isFalse);
  });
}
