import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Source name of a script that came from YouTube captions (FR-14).
const captionsSource = 'captions';

/// Source name of a script Groq wrote (FR-14).
const groqSource = 'groq-whisper-large-v3-turbo';

/// Which saved scripts belong together: one video, one requested language
/// (`auto` counts as its own language).
@immutable
class TranscriptKey {
  const TranscriptKey({required this.videoId, required this.language});

  final String videoId;
  final ScriptLanguage language;

  @override
  bool operator ==(Object other) =>
      other is TranscriptKey &&
      other.videoId == videoId &&
      other.language == language;

  @override
  int get hashCode => Object.hash(videoId, language);
}

/// A finished script kept for reuse (FR-14).
@immutable
class SavedTranscript {
  const SavedTranscript({
    required this.transcript,
    required this.source,
    required this.savedAt,
  });

  /// Throws [FormatException] when [json] isn't a saved script.
  factory SavedTranscript.fromJson(Map<String, Object?> json) {
    if (json case {
      'source': final String source,
      'savedAt': final String savedAt,
      'languageCode': final String languageCode,
      'lines': final List<Object?> lines,
    }) {
      return SavedTranscript(
        transcript: Transcript(
          languageCode: languageCode,
          lines: lines.map(lineFromJson).toList(),
        ),
        source: source,
        savedAt: DateTime.parse(savedAt),
      );
    }
    throw const FormatException('Not a saved script.');
  }

  final Transcript transcript;

  /// `captions` or `groq-whisper-large-v3-turbo`.
  final String source;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    'source': source,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'languageCode': transcript.languageCode,
    'lines': transcript.lines.map(lineToJson).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is SavedTranscript &&
      other.transcript == transcript &&
      other.source == source &&
      other.savedAt.isAtSameMomentAs(savedAt);

  @override
  int get hashCode =>
      Object.hash(transcript, source, savedAt.microsecondsSinceEpoch);
}

/// A video's finished script in one language, as the Recent list on Home
/// shows it (FR-11).
@immutable
class SavedScript {
  const SavedScript({
    required this.video,
    required this.language,
    required this.saved,
  });

  final SourceVideo video;

  /// The language that was asked for; `auto` scripts carry the detected
  /// one in [saved].
  final ScriptLanguage language;
  final SavedTranscript saved;

  TranscriptKey get key =>
      TranscriptKey(videoId: video.videoId, language: language);

  @override
  bool operator ==(Object other) =>
      other is SavedScript &&
      other.video == video &&
      other.language == language &&
      other.saved == saved;

  @override
  int get hashCode => Object.hash(video, language, saved);
}

/// Whisper's progress through an unfinished run: the lines of the first
/// [completedChunks] pieces (FR-14 Resume).
@immutable
class PartialTranscript {
  const PartialTranscript({required this.completedChunks, required this.lines});

  /// Throws [FormatException] when [json] isn't saved progress.
  factory PartialTranscript.fromJson(Map<String, Object?> json) {
    if (json case {
      'completedChunks': final int completedChunks,
      'lines': final List<Object?> lines,
    }) {
      return PartialTranscript(
        completedChunks: completedChunks,
        lines: lines.map(lineFromJson).toList(),
      );
    }
    throw const FormatException('Not saved progress.');
  }

  final int completedChunks;
  final List<TranscriptLine> lines;

  Map<String, Object?> toJson() => {
    'completedChunks': completedChunks,
    'lines': lines.map(lineToJson).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is PartialTranscript &&
      other.completedChunks == completedChunks &&
      listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(completedChunks, Object.hashAll(lines));
}

Map<String, Object?> lineToJson(TranscriptLine line) => {
  'index': line.index,
  'text': line.text,
  'startMs': line.start.inMilliseconds,
  'endMs': line.end.inMilliseconds,
};

/// Throws [FormatException] when [json] isn't a saved line.
TranscriptLine lineFromJson(Object? json) {
  if (json case {
    'index': final int index,
    'text': final String text,
    'startMs': final int startMs,
    'endMs': final int endMs,
  }) {
    return TranscriptLine(
      index: index,
      text: text,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    );
  }
  throw const FormatException('Not a saved line.');
}
