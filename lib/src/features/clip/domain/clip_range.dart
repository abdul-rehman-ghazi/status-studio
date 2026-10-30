import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

@immutable
class ClipRange {
  const ClipRange({required this.start, required this.end});

  factory ClipRange.fromLines(Transcript transcript, RangeSelected selection) {
    return ClipRange(
      start: transcript.lines[selection.start].start,
      end: transcript.lines[selection.end].end,
    );
  }

  static const minimumLength = Duration(seconds: 3);
  static const nudgeStep = Duration(milliseconds: 500);

  final Duration start;
  final Duration end;

  Duration get length => end - start;

  /// Moves the start by [delta]; a move that makes a rule worse is ignored.
  ClipRange nudgeStart(Duration delta, {required Duration videoDuration}) {
    final moved = copyWith(start: start + delta);
    return moved._worsensRules(this, videoDuration) ? this : moved;
  }

  /// Moves the end by [delta]; a move that makes a rule worse is ignored.
  ClipRange nudgeEnd(Duration delta, {required Duration videoDuration}) {
    final moved = copyWith(end: end + delta);
    return moved._worsensRules(this, videoDuration) ? this : moved;
  }

  // Judged against the clip before the move, so a clip that starts out too
  // short or past the video's end (from transcript timestamps) can still be
  // nudged back towards a valid range.
  bool _worsensRules(ClipRange before, Duration videoDuration) =>
      (start < Duration.zero && start < before.start) ||
      (end > videoDuration && end > before.end) ||
      (length < minimumLength && length < before.length);

  ClipRange copyWith({Duration? start, Duration? end}) {
    return ClipRange(start: start ?? this.start, end: end ?? this.end);
  }

  @override
  bool operator ==(Object other) =>
      other is ClipRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
