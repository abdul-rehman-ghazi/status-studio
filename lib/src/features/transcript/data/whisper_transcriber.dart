import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// One Whisper run over a video's audio pieces, possibly resuming after
/// [completedChunks] pieces whose lines ended at [firstIndex] − 1.
class ChunkTranscription {
  const ChunkTranscription({
    required this.chunks,
    required this.language,
    required this.model,
    this.completedChunks = 0,
    this.firstIndex = 0,
  });

  /// Every piece of the audio, in order, including finished ones.
  final List<File> chunks;
  final ScriptLanguage language;
  final SpeechModel model;
  final int completedChunks;
  final int firstIndex;
}

/// Runs Whisper over audio chunks one by one, keeping the model loaded
/// between them, and releases it when the run ends however it ends.
class WhisperTranscriber {
  WhisperTranscriber(this._whisper);

  final WhisperController _whisper;
  var _cancelled = false;

  /// Emits each remaining chunk's lines as soon as that chunk is written,
  /// timed from the start of the video.
  Stream<List<TranscriptLine>> transcribeChunks(ChunkTranscription job) async* {
    _cancelled = false;
    var nextIndex = job.firstIndex;
    try {
      for (
        var position = job.completedChunks;
        position < job.chunks.length;
        position++
      ) {
        if (_cancelled) {
          return;
        }
        final segments = await _transcribe(job.chunks[position], job);
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
    ChunkTranscription job,
  ) async {
    final result = await _whisper.transcribe(
      model: whisperModelFor(job.model),
      audioPath: chunk.path,
      lang: job.language.whisperCode,
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
