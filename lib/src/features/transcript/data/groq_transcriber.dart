import 'dart:io';

import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';

/// Segments Groq is this sure hold no speech are dropped. Provisional until
/// the M9 spike (§10 Q5) measures it on a music-only piece.
const groqNoSpeechCutoff = 0.6;

/// One Groq run over a video's `.m4a` pieces, possibly resuming after
/// [completedPieces] pieces whose lines ended at [firstIndex] − 1.
class GroqTranscription {
  const GroqTranscription({
    required this.pieces,
    required this.language,
    this.completedPieces = 0,
    this.firstIndex = 0,
  });

  final List<File> pieces;
  final ScriptLanguage language;
  final int completedPieces;
  final int firstIndex;
}

/// Sends audio pieces to Groq one by one (spec FR-12a), emitting what
/// [WhisperTranscriber] emits so the pipeline treats both alike. Groq
/// reports no progress inside a piece, so each piece is 0 then done.
class GroqTranscriber {
  GroqTranscriber(this._client);

  final GroqClient _client;
  var _cancelled = false;

  Stream<ChunkEvent> transcribePieces(GroqTranscription job) async* {
    _cancelled = false;
    var nextIndex = job.firstIndex;
    for (
      var position = job.completedPieces;
      position < job.pieces.length;
      position++
    ) {
      if (_cancelled) {
        return;
      }
      yield ChunkProgress(position: position, fraction: 0);
      final segments = await _client.transcribe(
        job.pieces[position],
        languageCode: job.language == ScriptLanguage.auto
            ? null
            : job.language.whisperCode,
      );
      final lines = linesFromSegments(
        _speech(segments),
        offset: transcriptionChunk * position,
        firstIndex: nextIndex,
      );
      nextIndex += lines.length;
      yield ChunkWritten(lines);
    }
  }

  /// Stops before the next piece.
  Future<void> cancel() async => _cancelled = true;

  List<SpeechSegment> _speech(List<GroqSegment> segments) => [
    for (final segment in segments)
      if (segment.noSpeechProbability < groqNoSpeechCutoff)
        SpeechSegment(from: segment.from, to: segment.to, text: segment.text),
  ];
}
