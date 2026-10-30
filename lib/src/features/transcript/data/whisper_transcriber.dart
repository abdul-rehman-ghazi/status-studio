import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Runs Whisper over audio chunks one by one, keeping the model loaded
/// between them, and releases it when the run ends however it ends.
class WhisperTranscriber {
  WhisperTranscriber(this._whisper);

  final WhisperController _whisper;
  var _cancelled = false;

  /// Emits each chunk's lines as soon as that chunk is written.
  Stream<List<TranscriptLine>> transcribeChunks(
    List<File> chunks, {
    required ScriptLanguage language,
    required SpeechModel model,
  }) async* {
    _cancelled = false;
    var nextIndex = 0;
    try {
      for (final (position, chunk) in chunks.indexed) {
        if (_cancelled) {
          return;
        }
        final segments = await _transcribe(chunk, language, model);
        final lines = linesFromSegments(
          segments,
          offset: transcriptionChunk * position,
          firstIndex: nextIndex,
        );
        nextIndex += lines.length;
        yield lines;
      }
    } finally {
      await _whisper.releaseModel();
    }
  }

  /// Stops before the next chunk. Whisper can't be interrupted inside one.
  Future<void> cancel() async => _cancelled = true;

  Future<List<SpeechSegment>> _transcribe(
    File chunk,
    ScriptLanguage language,
    SpeechModel model,
  ) async {
    final result = await _whisper.transcribe(
      model: whisperModelFor(model),
      audioPath: chunk.path,
      lang: language.whisperCode,
      withSegments: true,
      keepModelLoaded: true,
      suppressNonSpeechTokens: true,
    );
    if (result == null) {
      throw TranscriptionFailedException('Whisper failed on ${chunk.path}.');
    }
    return [
      for (final segment
          in result.transcription.segments ??
              const <WhisperTranscribeSegment>[])
        SpeechSegment(
          from: segment.fromTs,
          to: segment.toTs,
          text: segment.text,
        ),
    ];
  }
}

final whisperTranscriberProvider = Provider<WhisperTranscriber>(
  (ref) => WhisperTranscriber(WhisperController()),
);
