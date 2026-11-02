import 'package:flutter/foundation.dart';

/// Which transcript lines the user has picked for the clip (spec FR-4).
@immutable
sealed class LineSelection {
  const LineSelection();

  LineSelection tap(int index);

  bool isHighlighted(int index);
}

class NoSelection extends LineSelection {
  const NoSelection();

  @override
  LineSelection tap(int index) => StartSelected(index);

  @override
  bool isHighlighted(int index) => false;

  @override
  bool operator ==(Object other) => other is NoSelection;

  @override
  int get hashCode => (NoSelection).hashCode;
}

class StartSelected extends LineSelection {
  const StartSelected(this.start);

  final int start;

  @override
  LineSelection tap(int index) {
    if (index < start) {
      return StartSelected(index);
    }
    return RangeSelected(start, index);
  }

  @override
  bool isHighlighted(int index) => index == start;

  @override
  bool operator ==(Object other) =>
      other is StartSelected && other.start == start;

  @override
  int get hashCode => start.hashCode;
}

class RangeSelected extends LineSelection {
  const RangeSelected(this.start, this.end);

  final int start;
  final int end;

  @override
  LineSelection tap(int index) => StartSelected(index);

  @override
  bool isHighlighted(int index) => index >= start && index <= end;

  @override
  bool operator ==(Object other) =>
      other is RangeSelected && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
