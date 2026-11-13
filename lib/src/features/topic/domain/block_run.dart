import 'package:flutter/foundation.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// A run of transcript blocks being chosen for a moment (spec FR-36, M50;
/// the script page, FR-41): the first tap starts it, a later one sets its
/// end (inside the run too), and one before it starts it again there.
/// Positions are indexes into the transcript.
@immutable
class BlockRun {
  const BlockRun({required this.first, required this.last});

  final int first;
  final int last;

  /// The run after a tap on [index]; [current] is null before any tap.
  static BlockRun tapped(BlockRun? current, int index) {
    if (current == null || index < current.first) {
      return BlockRun(first: index, last: index);
    }
    return BlockRun(first: current.first, last: index);
  }

  bool includes(int index) => index >= first && index <= last;

  List<TranscriptBlock> of(List<TranscriptBlock> blocks) =>
      blocks.sublist(first, last + 1);

  @override
  bool operator ==(Object other) =>
      other is BlockRun && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

/// "Add 1:02:13–1:02:31 · 18 s" for a chosen run of blocks.
String addRunLabel(List<TranscriptBlock> run) =>
    'Add ${formatTimestamp(run.first.start)}–'
    '${formatTimestamp(run.last.end)} · '
    '${(run.last.end - run.first.start).inSeconds} s';
