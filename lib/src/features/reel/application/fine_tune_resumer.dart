import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_stores.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
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
    final scripts = await stores.scripts();
    final SavedTranscript script;
    try {
      script = await _finishedScript(scripts, saved.draft);
    } on NoSavedTranscriptException {
      return _onUnfinishedScript(saved, scripts);
    }
    if (saved.draft.fits(saved.video, script.transcript)) {
      return _ready(saved, script.transcript);
    }
    await _discard(saved.draft);
    return FineTuneScriptChanged(
      saved.draft.startOver(saved.video).withTranscript(script.transcript),
    );
  }

  /// The user left while the script was still being written: its lines so
  /// far count when they hold the picked ones, and the run carries on.
  Future<FineTuneResume> _onUnfinishedScript(
    SavedFineTune saved,
    TranscriptStore scripts,
  ) async {
    final Transcript transcript;
    try {
      transcript = await _unfinishedLines(scripts, saved.draft);
    } on NoSavedTranscriptException {
      return _gone(saved);
    }
    if (!saved.draft.fits(saved.video, transcript)) {
      return _gone(saved);
    }
    return _ready(saved, transcript);
  }

  FineTuneResume _ready(SavedFineTune saved, Transcript transcript) =>
      FineTuneReady(saved.draft.restoredOnto(saved.video, transcript));

  Future<FineTuneResume> _gone(SavedFineTune saved) async {
    await _discard(saved.draft);
    return FineTuneScriptGone(saved.draft.startOver(saved.video));
  }

  /// Edited lines live in the `edited` script, which a newer script of
  /// another source can hide from [TranscriptStore.load].
  Future<SavedTranscript> _finishedScript(
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

  /// The lines Groq had written, with the language it was asked for: the
  /// run that carries on replaces both.
  Future<Transcript> _unfinishedLines(
    TranscriptStore scripts,
    FineTuneDraft draft,
  ) async {
    final partial = await scripts.loadPartial(draft.script, groqSource);
    return Transcript(
      languageCode: draft.script.language.whisperCode,
      lines: partial.lines,
    );
  }

  Future<void> _discard(FineTuneDraft draft) async =>
      (await stores.drafts()).delete(draft.script);
}

final fineTuneResumerProvider = Provider<FineTuneResumer>(
  (ref) => FineTuneResumer(ref.read(fineTuneStoresProvider)),
);
