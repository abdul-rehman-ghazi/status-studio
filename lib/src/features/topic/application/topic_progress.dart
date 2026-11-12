import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// What finding the moments reports (spec FR-36).
sealed class TopicProgress {
  const TopicProgress();
}

/// A step under way; [fraction] is null when it can't be measured.
class TopicStep extends TopicProgress {
  const TopicStep(this.label, {this.fraction});

  final String label;
  final double? fraction;
}

/// Groq's free limit was reached; the search carries on by itself at
/// [resumesAt].
class WaitingForGroq extends TopicProgress {
  const WaitingForGroq(this.resumesAt);

  final DateTime resumesAt;
}

/// The cuts, in video order, and the transcript blocks for Add a moment.
class TopicFound extends TopicProgress {
  const TopicFound({required this.cuts, required this.blocks});

  final List<TopicCut> cuts;
  final List<TranscriptBlock> blocks;
}
