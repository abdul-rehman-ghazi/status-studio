import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/topic/domain/moment_candidate.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// One cut on Review cuts (spec FR-36): a stretch of the linked video, its
/// words and why it was picked.
@immutable
class TopicCut {
  const TopicCut({
    required this.start,
    required this.end,
    required this.text,
    required this.reason,
  });

  factory TopicCut.fromCandidate(
    MomentCandidate candidate,
    List<TranscriptBlock> blocks,
  ) {
    final run = blocks.sublist(candidate.firstBlock, candidate.lastBlock + 1);
    return TopicCut(
      start: run.first.start,
      end: run.last.end,
      text: candidate.text.isNotEmpty
          ? candidate.text
          : run.map((block) => block.text).join(' '),
      reason: candidate.reason,
    );
  }

  /// A run of blocks the user added from the transcript (spec FR-36, M50),
  /// first to last in video order; it has no reason.
  factory TopicCut.fromBlocks(List<TranscriptBlock> run) => TopicCut(
    start: run.first.start,
    end: run.last.end,
    text: run.map((block) => block.text).join(' '),
    reason: '',
  );

  final Duration start;
  final Duration end;
  final String text;
  final String reason;

  Duration get length => end - start;

  TopicCut withTimes({required Duration start, required Duration end}) =>
      TopicCut(start: start, end: end, text: text, reason: reason);

  @override
  bool operator ==(Object other) =>
      other is TopicCut &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(start, end, text, reason);
}

/// Shorter cuts are dropped: a blink between two joins.
const shortestCut = Duration(seconds: 2);

/// Every moment Groq found, as cuts in video order, for the user to tick
/// (spec FR-36). Of two that overlap, the higher score stays; moments under
/// two seconds are dropped.
List<TopicCut> candidatesAsCuts(
  List<MomentCandidate> candidates,
  List<TranscriptBlock> blocks,
) {
  final best = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <MomentCandidate>[];
  for (final candidate in best) {
    // A candidate naming blocks this transcript doesn't have is left out,
    // so a stale one can never break the list.
    if (candidate.lastBlock < blocks.length &&
        candidate.lengthIn(blocks) >= shortestCut &&
        !kept.any(candidate.overlaps)) {
      kept.add(candidate);
    }
  }
  kept.sort((a, b) => a.firstBlock.compareTo(b.firstBlock));
  return [
    for (final candidate in kept) TopicCut.fromCandidate(candidate, blocks),
  ];
}
