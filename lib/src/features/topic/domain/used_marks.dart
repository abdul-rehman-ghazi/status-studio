import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// The name of the newest of [reels] that used part of [start]–[end] of
/// the source, or null when none did (spec FR-44). Touching a used range
/// only at an edge doesn't count.
String? newestReelOver(Duration start, Duration end, List<RecentReel> reels) {
  RecentReel? newest;
  for (final reel in reels) {
    final overlaps = reel.usedRanges.any((range) => range.overlaps(start, end));
    if (overlaps &&
        (newest == null || reel.createdAt.isAfter(newest.createdAt))) {
      newest = reel;
    }
  }
  return newest?.title;
}

/// For each script block a reel of this video used, the newest such
/// reel's name, by block index (spec FR-44). [reels] are the linked
/// video's own.
Map<int, String> usedBlocks(
  List<TranscriptBlock> blocks,
  List<RecentReel> reels,
) {
  if (reels.isEmpty) {
    return const {};
  }
  return {
    for (final (index, block) in blocks.indexed)
      index: ?newestReelOver(block.start, block.end, reels),
  };
}
