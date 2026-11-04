import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const _addedLineLength = Duration(seconds: 2);
const _shortestTimedLine = Duration(seconds: 1);

/// A script and the lines picked from it, edited together so the range keeps
/// covering the same lines (spec FR-21).
@immutable
class PickedScript {
  const PickedScript({required this.transcript, required this.selection});

  final Transcript transcript;
  final RangeSelected selection;

  @override
  bool operator ==(Object other) =>
      other is PickedScript &&
      other.transcript == transcript &&
      other.selection == selection;

  @override
  int get hashCode => Object.hash(transcript, selection);
}

/// A blank [text] keeps the line as it was.
PickedScript withLineText(PickedScript script, int index, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return script;
  }
  final lines = [...script.transcript.lines];
  lines[index] = lines[index].copyWith(text: trimmed);
  return _withLines(script, lines, script.selection);
}

/// Moves the text at [from] to [to]. Times stay in their slots, so lines stay
/// in time order.
PickedScript withLineTextMoved(PickedScript script, int from, int to) {
  final lines = script.transcript.lines;
  final movedTexts = [for (final line in lines) line.text];
  movedTexts.insert(to, movedTexts.removeAt(from));
  return _withLines(script, [
    for (final (position, line) in lines.indexed)
      line.copyWith(text: movedTexts[position]),
  ], script.selection);
}

/// Inserts a line at [playhead]; the line it lands in ends there. A blank
/// [text] adds nothing.
PickedScript withLineAdded(
  PickedScript script, {
  required String text,
  required Duration playhead,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return script;
  }
  final lines = [...script.transcript.lines];
  final position = lines.indexWhere((line) => line.start > playhead);
  final insertAt = position < 0 ? lines.length : position;
  if (insertAt > 0) {
    lines[insertAt - 1] = _endedAt(lines[insertAt - 1], playhead);
  }
  lines.insert(
    insertAt,
    TranscriptLine(
      index: insertAt,
      text: trimmed,
      start: playhead,
      end: _addedLineEnd(lines, insertAt, playhead),
    ),
  );
  final selection = script.selection;
  return _withLines(
    script,
    lines,
    RangeSelected(
      insertAt <= selection.start ? selection.start + 1 : selection.start,
      insertAt <= selection.end ? selection.end + 1 : selection.end,
    ),
  );
}

TranscriptLine _endedAt(TranscriptLine line, Duration end) {
  final cuts = line.start < end && line.end > end;
  return cuts ? line.copyWith(end: end) : line;
}

Duration _addedLineEnd(
  List<TranscriptLine> lines,
  int insertAt,
  Duration start,
) {
  final end = start + _addedLineLength;
  final hasNext = insertAt < lines.length;
  if (hasNext && lines[insertAt].start < end) {
    return lines[insertAt].start;
  }
  return end;
}

/// Throws when [index] is the only picked line: the clip needs a line.
PickedScript withLineRemoved(PickedScript script, int index) {
  final selection = script.selection;
  if (selection.start == selection.end && selection.start == index) {
    throw StateError('The last picked line cannot be removed.');
  }
  final lines = [...script.transcript.lines]..removeAt(index);
  return _withLines(
    script,
    lines,
    RangeSelected(
      index < selection.start ? selection.start - 1 : selection.start,
      index <= selection.end ? selection.end - 1 : selection.end,
    ),
  );
}

/// Tap to time (spec FR-21): the line starts at [playhead] and the line that
/// was highlighted there ends there. A tap before the previous line's start
/// changes nothing.
PickedScript withLineTimedAt(
  PickedScript script,
  int index,
  Duration playhead,
) {
  final lines = [...script.transcript.lines];
  if (index > 0 && playhead < lines[index - 1].start) {
    return script;
  }
  final highlighted = highlightedLineIndex(lines, playhead);
  if (highlighted != null &&
      highlighted != index &&
      lines[highlighted].start < playhead) {
    lines[highlighted] = lines[highlighted].copyWith(end: playhead);
  }
  lines[index] = _startedAt(lines, index, playhead);
  final selection = script.selection;
  return _withLines(
    script,
    lines,
    RangeSelected(
      index < selection.start ? index : selection.start,
      index > selection.end ? index : selection.end,
    ),
  );
}

/// The line playing at [position], or none between lines (spec FR-21).
int? highlightedLineIndex(List<TranscriptLine> lines, Duration position) {
  for (final (index, line) in lines.indexed) {
    if (line.start <= position && position < line.end) {
      return index;
    }
  }
  return null;
}

TranscriptLine _startedAt(
  List<TranscriptLine> lines,
  int index,
  Duration start,
) {
  final line = lines[index];
  final length = line.end - line.start;
  var end = start + (length > _shortestTimedLine ? length : _shortestTimedLine);
  final hasNext = index + 1 < lines.length;
  if (hasNext &&
      lines[index + 1].start > start &&
      lines[index + 1].start < end) {
    end = lines[index + 1].start;
  }
  return line.copyWith(start: start, end: end);
}

PickedScript _withLines(
  PickedScript script,
  List<TranscriptLine> lines,
  RangeSelected selection,
) {
  return PickedScript(
    transcript: script.transcript.copyWith(
      lines: [
        for (final (position, line) in lines.indexed)
          line.copyWith(index: position),
      ],
    ),
    selection: selection,
  );
}
