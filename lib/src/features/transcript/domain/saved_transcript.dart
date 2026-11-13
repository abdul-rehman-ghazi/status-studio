import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:status_studio/src/core/json_converters.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

part 'saved_transcript.freezed.dart';
part 'saved_transcript.g.dart';

/// Source name of a script Groq wrote (FR-14).
///
/// Names the model: a script from an older model stays readable, but a
/// partial run of one is never resumed under another.
const groqSource = 'groq-whisper-large-v3';

/// Source name of a script the user edited on Lyrics (FR-21), or that an
/// AI fixed before M36 (FR-18, FR-19).
const editedSource = 'edited';

/// Source name of a linked clip's script translated by Groq's chat model
/// into the output language (spec FR-37).
const translatedSource = 'groq-translated';

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
///
/// Saved flat: `languageCode` and `lines` sit beside `source` and
/// `savedAt`, so `toJson` is written by hand.
@Freezed(equal: false, toJson: false)
abstract class SavedTranscript with _$SavedTranscript {
  @JsonSerializable(createToJson: false)
  const factory SavedTranscript({
    @JsonKey(readValue: readWholeObject)
    @_TranscriptConverter()
    required Transcript transcript,

    /// `groq-whisper-large-v3` (older scripts: `groq-whisper-large-v3-turbo`)
    /// or `edited`.
    required String source,
    required DateTime savedAt,
  }) = _SavedTranscript;

  const SavedTranscript._();

  /// Throws [CheckedFromJsonException] when [json] isn't a saved script.
  factory SavedTranscript.fromJson(Map<String, Object?> json) =>
      _$SavedTranscriptFromJson(json);

  Map<String, Object?> toJson() => {
    'source': source,
    'savedAt': savedAt.toUtc().toIso8601String(),
    ...const _TranscriptConverter().toJson(transcript),
  };

  // By moment, not by `DateTime ==`: a script saved with a local time must
  // equal the UTC one read back.
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
@freezed
abstract class PartialTranscript with _$PartialTranscript {
  const factory PartialTranscript({
    required int completedChunks,
    @_TranscriptLineConverter() required List<TranscriptLine> lines,
  }) = _PartialTranscript;

  /// Throws [CheckedFromJsonException] when [json] isn't saved progress.
  factory PartialTranscript.fromJson(Map<String, Object?> json) =>
      _$PartialTranscriptFromJson(json);
}

class _TranscriptConverter
    implements JsonConverter<Transcript, Map<String, Object?>> {
  const _TranscriptConverter();

  /// Throws [FormatException] when [json] doesn't hold a script's lines.
  @override
  Transcript fromJson(Map<String, Object?> json) {
    if (json case {
      'languageCode': final String languageCode,
      'lines': final List<Object?> lines,
    }) {
      return Transcript(
        languageCode: languageCode,
        lines: lines.map(_lineFromObject).toList(),
      );
    }
    throw const FormatException('Not a saved script.');
  }

  @override
  Map<String, Object?> toJson(Transcript transcript) => {
    'languageCode': transcript.languageCode,
    'lines': transcript.lines
        .map(const _TranscriptLineConverter().toJson)
        .toList(),
  };
}

TranscriptLine _lineFromObject(Object? json) {
  if (json is Map<String, Object?>) {
    return const _TranscriptLineConverter().fromJson(json);
  }
  throw const FormatException('Not a saved line.');
}

class _TranscriptLineConverter
    implements JsonConverter<TranscriptLine, Map<String, Object?>> {
  const _TranscriptLineConverter();

  /// Throws [FormatException] when [json] isn't a saved line.
  @override
  TranscriptLine fromJson(Map<String, Object?> json) {
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

  @override
  Map<String, Object?> toJson(TranscriptLine line) => {
    'index': line.index,
    'text': line.text,
    'startMs': line.start.inMilliseconds,
    'endMs': line.end.inMilliseconds,
  };
}
