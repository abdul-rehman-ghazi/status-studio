import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/lines_history.dart';

/// Undo and redo for the lines while Lyrics is open (spec FR-34). Lyrics
/// watches it, so it is cleared once Lyrics is gone.
final lyricsUndoProvider =
    NotifierProvider.autoDispose<LyricsUndoController, LinesHistory>(
      LyricsUndoController.new,
    );

class LyricsUndoController extends Notifier<LinesHistory> {
  @override
  LinesHistory build() => const LinesHistory();

  /// Applies [edit] to the lines and records how they were, unless it
  /// changed no line (an ignored tap).
  void applyEdit(PickedScript Function(PickedScript script) edit) {
    final before = ref.read(reelDraftProvider).linesSnapshot;
    ref.read(reelDraftProvider.notifier).editScript(edit);
    final after = ref.read(reelDraftProvider).linesSnapshot;
    if (after.transcript == before.transcript) {
      return;
    }
    state = state.recorded(before);
  }

  /// Does nothing when there is nothing to undo, so a late tap on an old
  /// quick message is harmless.
  void undo() {
    if (!state.canUndo) {
      return;
    }
    _take(state.undone(ref.read(reelDraftProvider).linesSnapshot));
  }

  void redo() {
    if (!state.canRedo) {
      return;
    }
    _take(state.redone(ref.read(reelDraftProvider).linesSnapshot));
  }

  /// Get and Get again replace the lines, so earlier steps no longer apply.
  void clear() => state = const LinesHistory();

  void _take(HistoryStep step) {
    state = step.history;
    ref.read(reelDraftProvider.notifier).restoreLines(step.restored);
    if (!step.restored.linesEdited) {
      _catchUpWithScript();
    }
  }

  /// Unedited lines follow the written script as it is now (spec FR-34): a
  /// run kept writing while the edits held its lines back.
  void _catchUpWithScript() {
    final progress = ref.read(scriptProgressProvider).value;
    if (progress == null) {
      return;
    }
    ref.read(reelDraftProvider.notifier).growTranscript(progress.transcript);
  }
}
