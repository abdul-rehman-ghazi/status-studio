import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// The lines that overlap [clip], first to last. Every line when none does,
/// so a clip over silence still has a script to work on.
///
/// Throws [StateError] for a transcript without lines.
RangeSelected linesInClip(Transcript transcript, ClipRange clip) {
  final lines = transcript.lines;
  if (lines.isEmpty) {
    throw StateError('A transcript without lines has no lines in the clip.');
  }
  final overlapping = [
    for (var index = 0; index < lines.length; index++)
      if (lines[index].end > clip.start && lines[index].start < clip.end) index,
  ];
  if (overlapping.isEmpty) {
    return RangeSelected(0, lines.length - 1);
  }
  return RangeSelected(overlapping.first, overlapping.last);
}
