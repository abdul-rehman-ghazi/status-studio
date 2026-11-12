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
      text: run.map((block) => block.text).join(' '),
      reason: candidate.reason,
    );
  }

  /// A block the user added from the transcript has no reason.
  factory TopicCut.fromBlock(TranscriptBlock block) => TopicCut(
    start: block.start,
    end: block.end,
    text: block.text,
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

/// The cuts for a clip of about [length] (spec FR-36): [ordered] is walked
/// best first, each trimmed from its end to the length still free under 110 % of [length], keeping a candidate of at least two seconds that overlaps no
/// kept one while the total stays within 110 % of [length], until it
/// reaches 90 %. The kept cuts come back in video order.
List<TopicCut> fitToLength({
  required List<MomentCandidate> ordered,
  required List<TranscriptBlock> blocks,
  required Duration length,
}) {
  final longest = length * 1.1;
  final enough = length * 0.9;
  final kept = <MomentCandidate>[];
  var total = Duration.zero;
  for (final whole in ordered) {
    if (total >= enough) {
      break;
    }
    final candidate = _trimmed(whole, blocks, longest - total);
    final candidateLength = candidate.lengthIn(blocks);
    final fits =
        candidateLength >= shortestCut &&
        total + candidateLength <= longest &&
        !kept.any(candidate.overlaps);
    if (fits) {
      kept.add(candidate);
      total += candidateLength;
    }
  }
  kept.sort((a, b) => a.firstBlock.compareTo(b.firstBlock));
  return [
    for (final candidate in kept) TopicCut.fromCandidate(candidate, blocks),
  ];
}

/// [candidate] without its last blocks until it fits in [room], the length
/// still free: the model often returns moments of 40 s or more, which would
/// otherwise leave a 60 s clip at one cut (§10 item 11).
MomentCandidate _trimmed(
  MomentCandidate candidate,
  List<TranscriptBlock> blocks,
  Duration room,
) {
  var lastBlock = candidate.lastBlock;
  while (lastBlock > candidate.firstBlock &&
      blocks[lastBlock].end - blocks[candidate.firstBlock].start > room) {
    lastBlock--;
  }
  return MomentCandidate(
    firstBlock: candidate.firstBlock,
    lastBlock: lastBlock,
    score: candidate.score,
    reason: candidate.reason,
  );
}

/// Best first by score, for when no picking call ran.
List<MomentCandidate> byScore(List<MomentCandidate> candidates) =>
    [...candidates]..sort((a, b) => b.score.compareTo(a.score));
