import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';

/// The script run in progress, shared by Processing and Script so the
/// user can start picking lines while the rest is still being written.
final scriptProgressProvider =
    NotifierProvider<ScriptProgressController, AsyncValue<ScriptProgress>>(
      ScriptProgressController.new,
    );

class ScriptProgressController extends Notifier<AsyncValue<ScriptProgress>> {
  StreamSubscription<ScriptProgress>? _subscription;

  @override
  AsyncValue<ScriptProgress> build() {
    ref.onDispose(_stopListening);
    return const AsyncLoading();
  }

  /// Saved script, captions or Whisper, whichever comes first (FR-3).
  void start(SourceVideo video, ScriptLanguage language) =>
      _follow(ref.read(scriptPipelineProvider).run(video, language));

  /// Whisper again, replacing the saved script (FR-14).
  void writeAgain(SourceVideo video, ScriptLanguage language) =>
      _follow(ref.read(scriptPipelineProvider).writeAgain(video, language));

  /// Stops the run; Whisper releases its model as the stream closes.
  void cancel() => _stopListening();

  void _follow(Stream<ScriptProgress> run) {
    _stopListening();
    state = const AsyncLoading();
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
    // Not awaited: a cancelled pipeline may only finish its current piece.
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
