import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_stores.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// How a kept fine-tune can be continued (spec FR-24).
sealed class FineTuneResume {
  const FineTuneResume();
}

/// The script is as it was: [draft] is the whole reel, ready for Fine-tune.
class FineTuneReady extends FineTuneResume {
  const FineTuneReady(this.draft);

  final ReelDraft draft;
}

/// No script is saved any more; [startOver] has the carried-over look and
/// waits for Processing to write the script again.
class FineTuneScriptGone extends FineTuneResume {
  const FineTuneScriptGone(this.startOver);

  final ReelDraft startOver;
}

/// The script differs from the one the lines were picked from; [startOver]
/// holds the current script and the carried-over look.
class FineTuneScriptChanged extends FineTuneResume {
  const FineTuneScriptChanged(this.startOver);

  final ReelDraft startOver;
}

class FineTuneResumer {
  const FineTuneResumer(this.stores);

  final FineTuneStores stores;

  /// Finds the script [saved] was picked from. When it can't be continued
  /// the kept fine-tune is deleted, since it would never open again.
  Future<FineTuneResume> resume(SavedFineTune saved) async {
    final draft = saved.draft;
    final scripts = await stores.scripts();
    try {
      final script = await _scriptOf(scripts, draft);
      if (draft.fits(saved.video, script.transcript)) {
        return FineTuneReady(
          draft.restoredOnto(saved.video, script.transcript),
        );
      }
      await _discard(draft);
      return FineTuneScriptChanged(
        draft.startOver(saved.video).withTranscript(script.transcript),
      );
    } on NoSavedTranscriptException {
      await _discard(draft);
      return FineTuneScriptGone(draft.startOver(saved.video));
    }
  }

  /// Edited lines live in the `edited` script, which a newer script of
  /// another source can hide from [TranscriptStore.load].
  Future<SavedTranscript> _scriptOf(
    TranscriptStore scripts,
    FineTuneDraft draft,
  ) async {
    if (!draft.linesEdited) {
      return scripts.load(draft.script);
    }
    try {
      return await scripts.loadFromSource(draft.script, editedSource);
    } on NoSavedTranscriptException {
      return scripts.load(draft.script);
    }
  }

  Future<void> _discard(FineTuneDraft draft) async =>
      (await stores.drafts()).delete(draft.script);
}

final fineTuneResumerProvider = Provider<FineTuneResumer>(
  (ref) => FineTuneResumer(ref.read(fineTuneStoresProvider)),
);
