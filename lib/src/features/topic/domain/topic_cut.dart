import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// One moment on Review cuts (spec FR-36, FR-43): a stretch of the linked
/// video and its words. The user chose it, so it has no reason (M53).
@immutable
class TopicCut {
  const TopicCut({required this.start, required this.end, required this.text});

  /// A run of blocks the user added from the script (spec FR-41), first to
  /// last in video order.
  factory TopicCut.fromBlocks(List<TranscriptBlock> run) => TopicCut(
    start: run.first.start,
    end: run.last.end,
    text: run.map((block) => block.text).join(' '),
  );

  final Duration start;
  final Duration end;
  final String text;

  Duration get length => end - start;

  TopicCut withTimes({required Duration start, required Duration end}) =>
      TopicCut(start: start, end: end, text: text);

  @override
  bool operator ==(Object other) =>
      other is TopicCut &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}

/// Shorter cuts are refused: a blink between two joins.
const shortestCut = Duration(seconds: 2);
