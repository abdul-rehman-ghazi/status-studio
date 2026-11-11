import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// The lines that overlap [clip], first to last; none for a clip over a
/// stretch with no sung line, so its caption stays empty (spec FR-21, M40).
///
/// Throws [StateError] for a transcript without lines.
LineSelection linesInClip(Transcript transcript, ClipRange clip) {
  final lines = transcript.lines;
  if (lines.isEmpty) {
    throw StateError('A transcript without lines has no lines in the clip.');
  }
  final overlapping = [
    for (var index = 0; index < lines.length; index++)
      if (lines[index].end > clip.start && lines[index].start < clip.end) index,
  ];
  if (overlapping.isEmpty) {
    return const NoSelection();
  }
  return RangeSelected(overlapping.first, overlapping.last);
}
