import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// What getting a linked video's script reports (spec FR-36, FR-43).
sealed class TopicProgress {
  const TopicProgress();
}

/// A step under way; [fraction] is null when it can't be measured.
class TopicStep extends TopicProgress {
  const TopicStep(this.label, {this.fraction});

  final String label;
  final double? fraction;
}

/// The script's blocks, for the user to pick moments from (spec FR-43).
class TopicFound extends TopicProgress {
  const TopicFound(this.blocks);

  final List<TranscriptBlock> blocks;
}
