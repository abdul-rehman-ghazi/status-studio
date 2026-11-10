import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_notices.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';

/// The script run of the reel being made (spec FR-3, M30). It belongs to the
/// reel, not to a screen: it keeps going when Lyrics closes. `null` means no
/// run was started, or the last one was cancelled.
final scriptProgressProvider =
    NotifierProvider<ScriptProgressController, AsyncValue<ScriptProgress?>>(
      ScriptProgressController.new,
    );

class ScriptProgressController extends Notifier<AsyncValue<ScriptProgress?>> {
  StreamSubscription<ScriptProgress>? _subscription;

  /// Completes once the last cancelled run has stopped.
  Future<void> _previousStopped = Future.value();

  /// Bumped by every start and cancel, so a run still waiting for the
  /// previous one to stop knows it has been replaced.
  var _generation = 0;

  @override
  AsyncValue<ScriptProgress?> build() {
    ref
      ..onDispose(_stop)
      // A new reel or another video makes the running script useless.
      ..listen(
        reelDraftProvider.select((draft) => draft.video),
        (previous, next) => cancel(),
      );
    return const AsyncData(null);
  }

  /// Saved script, captions or Groq, whichever comes first (FR-3).
  void start(SourceVideo video, ScriptLanguage language) => _follow(
    _keptRunning(ref.read(scriptPipelineProvider).run(video, language), video),
  );

  /// Groq again, replacing the saved script (FR-14).
  void writeAgain(SourceVideo video, ScriptLanguage language) => _follow(
    _keptRunning(
      ref.read(scriptPipelineProvider).writeAgain(video, language),
      video,
    ),
  );

  /// Stops the run and forgets it.
  void cancel() {
    _stop();
    state = const AsyncData(null);
  }

  void _stop() {
    _generation++;
    _stopListening();
  }

  /// Keeps writing when the user leaves the app or locks the phone
  /// (FR-16).
  Stream<ScriptProgress> _keptRunning(
    Stream<ScriptProgress> run,
    SourceVideo video,
  ) => ref.read(backgroundWorkProvider).keepRunning(run, ScriptNotices(video));

  void _follow(Stream<ScriptProgress> run) {
    _stop();
    state = const AsyncLoading();
    unawaited(_followOnceStopped(run, _generation));
  }

  /// A cancelled run keeps going until its current step ends (a download,
  /// an FFmpeg run, a Groq piece). Two runs at once would share audio
  /// files, so the next one waits.
  Future<void> _followOnceStopped(
    Stream<ScriptProgress> run,
    int generation,
  ) async {
    await _previousStopped;
    if (generation != _generation) {
      return;
    }
    _subscription = run.listen(
      _onProgress,
      onError: (Object error, StackTrace stackTrace) =>
          state = AsyncError(error, stackTrace),
    );
  }

  void _onProgress(ScriptProgress progress) {
    ref.read(reelDraftProvider.notifier).growTranscript(progress.transcript);
    state = AsyncData(progress);
  }

  void _stopListening() {
    final stopping = _subscription?.cancel();
    _subscription = null;
    if (stopping != null) {
      // An abandoned run's failure is no longer the user's concern.
      _previousStopped = stopping.then((_) {}, onError: (Object _) {});
    }
  }
}
