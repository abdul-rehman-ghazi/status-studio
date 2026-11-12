import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/real_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/translating_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// In run order, so screens can compare stages with `index`.
enum ScriptStage {
  preparingAudio('Cleaning the voice'),
  detectingLanguage('Detecting the language'),
  transcribing('Writing the script'),
  // Only for a clip joined from a link (spec FR-37).
  translating('Translating the lyrics'),
  // The last step the run shows; once it's reached the script is done.
  done('Lining up timestamps');

  const ScriptStage(this.label);

  /// The step's name on Lyrics and in the background notification.
  final String label;
}

class ScriptProgress {
  const ScriptProgress({
    required this.stage,
    required this.fraction,
    required this.transcript,
    this.savedAt,
    this.step,
    this.translatesTo,
  });

  final ScriptStage stage;

  /// Overall progress from 0 to 1.
  final double fraction;

  /// The lines written so far; complete once [stage] is done.
  final Transcript transcript;

  /// When the script was saved, if it was reopened from the saved scripts
  /// instead of written now (FR-14).
  final DateTime? savedAt;

  /// How much of [stage] is done, for the stages that can be measured:
  /// audio read for preparing it, audio written for transcribing.
  final WorkAmount? step;

  /// The language the lines are translated into, for a clip joined from a
  /// link (spec FR-37); null when the lines stay as spoken.
  final ScriptLanguage? translatesTo;
}

/// Turns a video into a transcript.
abstract interface class ScriptPipeline {
  /// A saved script if there is one, else captions, else Groq (FR-3).
  Stream<ScriptProgress> run(SourceVideo video, ScriptLanguage language);

  /// Groq only, replacing any saved script ("Write it again", FR-14).
  Stream<ScriptProgress> writeAgain(SourceVideo video, ScriptLanguage language);
}

/// The app's pipeline; tests override it with [FakeScriptPipeline].
final scriptPipelineProvider = Provider<ScriptPipeline>(
  (ref) =>
      translatingScriptPipeline(ref, ref.watch(realScriptPipelineProvider)),
);
