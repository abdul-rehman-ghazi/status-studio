import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// In run order, so screens can compare stages with `index`.
enum ScriptStage {
  downloadingModel,
  downloadingAudio,
  detectingLanguage,
  transcribing,
  done,
}

class ScriptProgress {
  const ScriptProgress({
    required this.stage,
    required this.fraction,
    required this.transcript,
  });

  final ScriptStage stage;

  /// Overall progress from 0 to 1.
  final double fraction;

  /// The lines written so far; complete once [stage] is done.
  final Transcript transcript;
}

/// Turns a video into a transcript: download, detect, transcribe.
abstract interface class ScriptPipeline {
  Stream<ScriptProgress> run(SourceVideo video, ScriptLanguage language);
}

final scriptPipelineProvider = Provider<ScriptPipeline>(
  (ref) => const FakeScriptPipeline(),
);
