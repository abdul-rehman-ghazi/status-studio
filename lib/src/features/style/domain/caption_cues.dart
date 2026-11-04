import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// One caption line and when it shows, counted from the clip's start
/// (spec FR-7a).
@immutable
class CaptionCue {
  const CaptionCue({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is CaptionCue &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);
}

/// The cue showing at [time] counted from the clip's start, or none between
/// lines. A cue's end is exclusive, so back-to-back lines never overlap.
CaptionCue? cueDueAt(List<CaptionCue> cues, Duration time) {
  for (final cue in cues) {
    if (cue.start <= time && time < cue.end) {
      return cue;
    }
  }
  return null;
}

/// The caption's lines, each with its own time (spec FR-7a).
///
/// While the caption still has one line per picked script line, each shows
/// when that script line is spoken. Once the user adds or removes lines the
/// pairing is lost, so the clip is shared out by line length instead.
List<CaptionCue> buildCaptionCues({
  required String captionText,
  required List<TranscriptLine> spokenLines,
  required ClipRange clip,
}) {
  final texts = captionText
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (texts.isEmpty) {
    return const [];
  }
  final cues = texts.length == spokenLines.length
      ? _atSpokenTimes(texts, spokenLines, clip)
      : _sharedByLength(texts, clip.length);
  return cues.where((cue) => cue.end > cue.start).toList();
}

List<CaptionCue> _atSpokenTimes(
  List<String> texts,
  List<TranscriptLine> spokenLines,
  ClipRange clip,
) {
  return [
    for (final (position, text) in texts.indexed)
      CaptionCue(
        text: text,
        start: _clamped(spokenLines[position].start - clip.start, clip.length),
        end: _clamped(spokenLines[position].end - clip.start, clip.length),
      ),
  ];
}

List<CaptionCue> _sharedByLength(List<String> texts, Duration clipLength) {
  final totalCharacters = texts.fold<int>(0, (sum, text) => sum + text.length);
  final cues = <CaptionCue>[];
  var charactersBefore = 0;
  for (final text in texts) {
    final start = clipLength * charactersBefore ~/ totalCharacters;
    charactersBefore += text.length;
    final end = clipLength * charactersBefore ~/ totalCharacters;
    cues.add(CaptionCue(text: text, start: start, end: end));
  }
  return cues;
}

Duration _clamped(Duration time, Duration clipLength) {
  if (time < Duration.zero) {
    return Duration.zero;
  }
  return time > clipLength ? clipLength : time;
}
