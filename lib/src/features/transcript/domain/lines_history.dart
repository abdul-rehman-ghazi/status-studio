import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// The lines as they were at one step: the script and whether it had been
/// edited by hand (spec FR-34). The selection is not kept: it always follows
/// the clip.
@immutable
class LinesSnapshot {
  const LinesSnapshot({required this.transcript, required this.linesEdited});

  final Transcript transcript;
  final bool linesEdited;

  @override
  bool operator ==(Object other) =>
      other is LinesSnapshot &&
      other.transcript == transcript &&
      other.linesEdited == linesEdited;

  @override
  int get hashCode => Object.hash(transcript, linesEdited);
}

/// A step taken back or forward: the history after it and the lines to show.
typedef HistoryStep = ({LinesHistory history, LinesSnapshot restored});

/// Undo and redo for the lines on Lyrics (spec FR-34).
@immutable
class LinesHistory {
  const LinesHistory({this.undoable = const [], this.redoable = const []});

  static const maxSteps = 50;

  /// Oldest first; the last is undone next.
  final List<LinesSnapshot> undoable;

  /// Oldest first; the last is redone next.
  final List<LinesSnapshot> redoable;

  bool get canUndo => undoable.isNotEmpty;
  bool get canRedo => redoable.isNotEmpty;

  /// After an edit made from [before]: a new step, Redo cleared, and the
  /// oldest step dropped beyond [maxSteps].
  LinesHistory recorded(LinesSnapshot before) {
    final steps = [...undoable, before];
    final overflow = steps.length - maxSteps;
    return LinesHistory(
      undoable: overflow > 0 ? steps.sublist(overflow) : steps,
    );
  }

  /// Takes back the last step from [current]. Throws [StateError] when
  /// there is nothing to undo.
  HistoryStep undone(LinesSnapshot current) {
    if (!canUndo) {
      throw StateError('Nothing to undo.');
    }
    return (
      history: LinesHistory(
        undoable: undoable.sublist(0, undoable.length - 1),
        redoable: [...redoable, current],
      ),
      restored: undoable.last,
    );
  }

  /// Makes the last undone step again from [current]. Throws [StateError]
  /// when there is nothing to redo.
  HistoryStep redone(LinesSnapshot current) {
    if (!canRedo) {
      throw StateError('Nothing to redo.');
    }
    return (
      history: LinesHistory(
        undoable: [...undoable, current],
        redoable: redoable.sublist(0, redoable.length - 1),
      ),
      restored: redoable.last,
    );
  }
}
