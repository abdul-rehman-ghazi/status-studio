import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/domain/audio_piece.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/groq_usage.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// What a run reports: progress inside a piece, or a finished piece's
/// lines.
sealed class ChunkEvent {
  const ChunkEvent();
}

/// The piece at [position] is [fraction] of the way through.
@immutable
class ChunkProgress extends ChunkEvent {
  const ChunkProgress({required this.position, required this.fraction});

  final int position;
  final double fraction;

  @override
  bool operator ==(Object other) =>
      other is ChunkProgress &&
      other.position == position &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(position, fraction);
}

/// A piece's lines, once it is written.
class ChunkWritten extends ChunkEvent {
  const ChunkWritten(this.lines);

  final List<TranscriptLine> lines;
}

/// One Groq run over a video's FLAC pieces, possibly resuming after
/// [completedPieces] pieces whose lines ended at [firstIndex] − 1.
class GroqTranscription {
  const GroqTranscription({
    required this.pieces,
    required this.language,
    required this.audioLength,
    this.completedPieces = 0,
    this.firstIndex = 0,
  });

  final List<AudioPiece> pieces;
  final ScriptLanguage language;

  /// Where the last piece ends, for counting what was sent (FR-45).
  final Duration audioLength;
  final int completedPieces;
  final int firstIndex;
}

/// Sends audio pieces to Groq one by one (spec FR-12a), emitting what
/// [WhisperTranscriber] emits so the pipeline treats both alike. Groq
/// reports no progress inside a piece, so each piece is 0 then done.
class GroqTranscriber {
  GroqTranscriber(this._client, this._usage);

  final GroqClient _client;
  final GroqUsageRecorder _usage;
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
      final piece = job.pieces[position];
      final segments = await _transcribe(piece, job.language);
      await _usage.audioSent(_lengthOf(job, position));
      final lines = linesFromSegments(
        _speech(segments),
        offset: piece.start,
        firstIndex: nextIndex,
      );
      nextIndex += lines.length;
      yield ChunkWritten(lines);
    }
  }

  /// A refusal for Groq's limit is counted, so the figure shows none left
  /// until Groq's wait ends (spec FR-45).
  Future<List<GroqSegment>> _transcribe(
    AudioPiece piece,
    ScriptLanguage language,
  ) async {
    try {
      return await _client.transcribe(
        piece.file,
        languageCode: language == ScriptLanguage.auto
            ? null
            : language.whisperCode,
      );
    } on GroqRateLimitedException catch (refusal) {
      await _usage.limitReached(refusal.retryAfter);
      rethrow;
    }
  }

  Duration _lengthOf(GroqTranscription job, int position) {
    final pieces = job.pieces;
    final end = position + 1 < pieces.length
        ? pieces[position + 1].start
        : job.audioLength;
    return end - pieces[position].start;
  }

  /// Stops before the next piece.
  Future<void> cancel() async => _cancelled = true;

  List<SpeechSegment> _speech(List<GroqSegment> segments) {
    final spoken = [
      for (final segment in segments)
        if (segment.noSpeechProbability < groqNoSpeechCutoff)
          SpeechSegment(from: segment.from, to: segment.to, text: segment.text),
    ];
    return _isOnlyHallucination(spoken) ? const [] : spoken;
  }
}

/// What turbo writes for silence and music, which it also scores as 0
/// `no_speech_prob` (spike, §10 Q5). Compared in [_normalised] form.
const _knownHallucinations = {
  'thank you',
  'thank you for watching',
  'thanks',
  'thanks for watching',
  'you',
  'bye',
};

/// Only a piece made entirely of known phrases is dropped: the same words
/// beside real speech, like a talk ending in "Thank you.", are kept.
bool _isOnlyHallucination(List<SpeechSegment> segments) =>
    segments.isNotEmpty &&
    segments.every(
      (segment) => _knownHallucinations.contains(_normalised(segment.text)),
    );

String _normalised(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
