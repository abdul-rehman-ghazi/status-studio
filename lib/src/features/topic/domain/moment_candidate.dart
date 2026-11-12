import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

/// A run of blocks Groq found about the topic (spec FR-36).
@immutable
class MomentCandidate {
  const MomentCandidate({
    required this.firstBlock,
    required this.lastBlock,
    required this.score,
    required this.reason,
  });

  factory MomentCandidate.fromJson(Map<String, Object?> json) =>
      MomentCandidate(
        firstBlock: json['first']! as int,
        lastBlock: json['last']! as int,
        score: (json['score']! as num).toDouble(),
        reason: json['reason']! as String,
      );

  final int firstBlock;
  final int lastBlock;

  /// From 0 (barely about it) to 1 (exactly about it).
  final double score;

  /// One line in English on why it fits, shown on the cut's card.
  final String reason;

  Map<String, Object?> toJson() => {
    'first': firstBlock,
    'last': lastBlock,
    'score': score,
    'reason': reason,
  };

  bool overlaps(MomentCandidate other) =>
      firstBlock <= other.lastBlock && other.firstBlock <= lastBlock;

  Duration lengthIn(List<TranscriptBlock> blocks) =>
      blocks[lastBlock].end - blocks[firstBlock].start;

  @override
  bool operator ==(Object other) =>
      other is MomentCandidate &&
      other.firstBlock == firstBlock &&
      other.lastBlock == lastBlock &&
      other.score == score &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(firstBlock, lastBlock, score, reason);
}

/// The candidates in a part's reply, `{"moments": [{first, last, score,
/// reason}]}`. Entries naming blocks outside [part], or in the wrong order,
/// are dropped: the model sometimes invents numbers. Throws
/// [GroqUnreadableReplyException] when the reply has no `moments` list.
List<MomentCandidate> candidatesFromReply(
  Map<String, Object?> reply,
  List<TranscriptBlock> part,
) {
  final moments = reply['moments'];
  if (moments is! List<Object?>) {
    throw const GroqUnreadableReplyException('No moments list.');
  }
  final firstNumber = part.first.number;
  final lastNumber = part.last.number;
  return moments
      .whereType<Map<String, Object?>>()
      .map(_candidateOrNull)
      .whereType<MomentCandidate>()
      .where(
        (candidate) =>
            candidate.firstBlock >= firstNumber &&
            candidate.lastBlock <= lastNumber &&
            candidate.firstBlock <= candidate.lastBlock,
      )
      .toList();
}

/// Null for an entry missing a field, which the caller drops.
MomentCandidate? _candidateOrNull(Map<String, Object?> json) {
  try {
    return MomentCandidate.fromJson(json);
  } on TypeError {
    return null;
  }
}

/// The candidate positions in the picking reply, `{"order": [3, 0, 5]}`,
/// best first; unknown and repeated positions are dropped. Throws
/// [GroqUnreadableReplyException] when the reply has no `order` list.
List<int> pickOrderFromReply(Map<String, Object?> reply, int candidateCount) {
  final order = reply['order'];
  if (order is! List<Object?>) {
    throw const GroqUnreadableReplyException('No order list.');
  }
  final seen = <int>{};
  return order
      .whereType<int>()
      .where((position) => position >= 0 && position < candidateCount)
      .where(seen.add)
      .toList();
}
