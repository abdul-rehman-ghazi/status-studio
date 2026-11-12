import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// One press of − or + on Review cuts (spec FR-36).
const cutNudge = Duration(milliseconds: 500);

/// A change to one edge of one cut.
class CutNudge {
  const CutNudge({
    required this.index,
    this.startBy = Duration.zero,
    this.endBy = Duration.zero,
  });

  final int index;
  final Duration startBy;
  final Duration endBy;
}

/// [cuts] with [nudge] applied, or unchanged when it would make the cut
/// shorter than two seconds, leave the video, or run into another cut.
List<TopicCut> nudgeCut(
  List<TopicCut> cuts,
  CutNudge nudge, {
  required Duration videoLength,
}) {
  final cut = cuts[nudge.index];
  final moved = cut.withTimes(
    start: cut.start + nudge.startBy,
    end: cut.end + nudge.endBy,
  );
  final others = [...cuts]..removeAt(nudge.index);
  final allowed =
      moved.start >= Duration.zero &&
      moved.end <= videoLength &&
      moved.length >= shortestCut &&
      !others.any((other) => _overlap(moved, other));
  if (!allowed) {
    return cuts;
  }
  return [...cuts]..[nudge.index] = moved;
}

/// [cuts] with [block] added where it falls in video order; unchanged when
/// it overlaps a cut already there.
List<TopicCut> addBlockAsCut(List<TopicCut> cuts, TranscriptBlock block) {
  final added = TopicCut.fromBlock(block);
  if (cuts.any((cut) => _overlap(added, cut))) {
    return cuts;
  }
  final position = cuts.indexWhere((cut) => cut.start > added.start);
  return [...cuts]..insert(position == -1 ? cuts.length : position, added);
}

Duration totalLength(List<TopicCut> cuts) =>
    cuts.fold(Duration.zero, (total, cut) => total + cut.length);

bool _overlap(TopicCut a, TopicCut b) => a.start < b.end && b.start < a.end;
