import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// One press of − or + on Review cuts (spec FR-36).
const cutNudge = Duration(milliseconds: 500);

/// A moment on Review cuts and whether it goes into the clip (spec FR-36).
/// Ticked cuts may not overlap each other; unticked ones may.
@immutable
class ReviewCut {
  const ReviewCut({
    required this.cut,
    required this.ticked,
    this.needsWords = false,
  });

  final TopicCut cut;
  final bool ticked;

  /// Its words no longer match its times (an edge moved), or are the
  /// transcript's own (added from it); Update words rewrites them (spec
  /// FR-40).
  final bool needsWords;

  /// [changed] times: the words wait for Update words.
  ReviewCut moved(TopicCut changed) =>
      ReviewCut(cut: changed, ticked: ticked, needsWords: true);

  /// [text] written for the times as they are.
  ReviewCut withWords(String text) => ReviewCut(
    cut: TopicCut(
      start: cut.start,
      end: cut.end,
      text: text,
      reason: cut.reason,
    ),
    ticked: ticked,
  );

  ReviewCut toggled() =>
      ReviewCut(cut: cut, ticked: !ticked, needsWords: needsWords);

  @override
  bool operator ==(Object other) =>
      other is ReviewCut &&
      other.cut == cut &&
      other.ticked == ticked &&
      other.needsWords == needsWords;

  @override
  int get hashCode => Object.hash(cut, ticked, needsWords);
}

/// Every moment found, none ticked: the user chooses (spec FR-36).
List<ReviewCut> untickedCuts(List<TopicCut> cuts) => [
  for (final cut in cuts) ReviewCut(cut: cut, ticked: false),
];

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
/// shorter than two seconds, leave the video, or, for a ticked cut, run
/// into another ticked one.
List<ReviewCut> nudgeCut(
  List<ReviewCut> cuts,
  CutNudge nudge, {
  required Duration videoLength,
}) {
  final review = cuts[nudge.index];
  final moved = review.cut.withTimes(
    start: review.cut.start + nudge.startBy,
    end: review.cut.end + nudge.endBy,
  );
  final allowed =
      moved.start >= Duration.zero &&
      moved.end <= videoLength &&
      moved.length >= shortestCut &&
      !(review.ticked && _overlapsTicked(cuts, moved, except: nudge.index));
  if (!allowed) {
    return cuts;
  }
  return [...cuts]..[nudge.index] = review.moved(moved);
}

/// [cuts] with the one at [index] ticked or unticked; ticking is refused
/// while it overlaps a ticked cut.
List<ReviewCut> toggleCut(List<ReviewCut> cuts, int index) {
  final review = cuts[index];
  if (!review.ticked && _overlapsTicked(cuts, review.cut, except: index)) {
    return cuts;
  }
  return [...cuts]..[index] = review.toggled();
}

/// [cuts] with the run of blocks [run] added as one moment, ticked, where
/// it falls in video order; unchanged when it overlaps a ticked cut.
List<ReviewCut> addBlocksAsCut(
  List<ReviewCut> cuts,
  List<TranscriptBlock> run,
) {
  final added = TopicCut.fromBlocks(run);
  if (_overlapsTicked(cuts, added, except: -1)) {
    return cuts;
  }
  final position = cuts.indexWhere((review) => review.cut.start > added.start);
  return [...cuts]..insert(
    position == -1 ? cuts.length : position,
    ReviewCut(cut: added, ticked: true, needsWords: true),
  );
}

/// The moments whose words wait for Update words (spec FR-40).
List<TopicCut> cutsNeedingWords(List<ReviewCut> cuts) => [
  for (final review in cuts)
    if (review.needsWords) review.cut,
];

/// [cuts] with each moment in [written] given its new words, matched by its
/// times as sent; a moment trimmed again meanwhile keeps waiting.
List<ReviewCut> withWrittenWords(
  List<ReviewCut> cuts,
  Map<TopicCut, String> written,
) => [
  for (final review in cuts)
    if (written[review.cut] case final text?)
      review.withWords(text)
    else
      review,
];

/// What goes into the clip, in the list's order.
List<TopicCut> tickedCuts(List<ReviewCut> cuts) => [
  for (final review in cuts)
    if (review.ticked) review.cut,
];

Duration totalLength(List<TopicCut> cuts) =>
    cuts.fold(Duration.zero, (total, cut) => total + cut.length);

bool _overlapsTicked(
  List<ReviewCut> cuts,
  TopicCut cut, {
  required int except,
}) => cuts.indexed.any(
  (entry) =>
      entry.$1 != except &&
      entry.$2.ticked &&
      cut.start < entry.$2.cut.end &&
      entry.$2.cut.start < cut.end,
);
