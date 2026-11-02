import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Length of the audio pieces Whisper transcribes one at a time (FR-3).
const transcriptionChunk = Duration(seconds: 90);

/// One stretch of speech as Whisper reports it, timed within its chunk.
@immutable
class SpeechSegment {
  const SpeechSegment({
    required this.from,
    required this.to,
    required this.text,
  });

  final Duration from;
  final Duration to;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SpeechSegment &&
      other.from == from &&
      other.to == to &&
      other.text == text;

  @override
  int get hashCode => Object.hash(from, to, text);
}

/// Whisper's markers for silence and music: `[BLANK_AUDIO]`, `(music)`, `♪`.
final _nonSpeech = RegExp(r'^(\[.*\]|\(.*\)|[♪♫♬♩\s]+)$');

/// Transcript lines from one chunk's [segments], timed from the start of
/// the video ([offset] is the chunk's start) and numbered from [firstIndex].
List<TranscriptLine> linesFromSegments(
  List<SpeechSegment> segments, {
  required Duration offset,
  required int firstIndex,
}) {
  final spoken = segments
      .map((segment) => (segment: segment, text: segment.text.trim()))
      .where(
        (entry) => entry.text.isNotEmpty && !_nonSpeech.hasMatch(entry.text),
      )
      .toList();
  return [
    for (final (position, entry) in spoken.indexed)
      TranscriptLine(
        index: firstIndex + position,
        text: entry.text,
        start: offset + entry.segment.from,
        end: offset + entry.segment.to,
      ),
  ];
}
