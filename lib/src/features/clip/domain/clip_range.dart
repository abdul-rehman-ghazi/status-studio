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
  /// [playable] is the part of the video a clip can cover: from the picture
  /// start to the end (spec FR-5).
  ClipRange nudgeStart(Duration delta, {required ClipRange playable}) {
    final moved = copyWith(start: start + delta);
    return moved._worsensRules(this, playable) ? this : moved;
  }

  /// Moves the end by [delta]; see [nudgeStart].
  ClipRange nudgeEnd(Duration delta, {required ClipRange playable}) {
    final moved = copyWith(end: end + delta);
    return moved._worsensRules(this, playable) ? this : moved;
  }

  /// This clip with its start moved up to [earliest] when it is before it;
  /// the end stays.
  ClipRange startingNoEarlierThan(Duration earliest) =>
      start < earliest ? copyWith(start: earliest) : this;

  // Judged against the clip before the move, so a clip that starts out too
  // short or past the video's end (from transcript timestamps) can still be
  // nudged back towards a valid range.
  bool _worsensRules(ClipRange before, ClipRange playable) =>
      (start < playable.start && start < before.start) ||
      (end > playable.end && end > before.end) ||
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
