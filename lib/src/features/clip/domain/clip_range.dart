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

  /// Moves the start by [delta]; a move that breaks a rule is ignored.
  ClipRange nudgeStart(Duration delta, {required Duration videoDuration}) {
    final moved = copyWith(start: start + delta);
    return moved._fitsIn(videoDuration) ? moved : this;
  }

  /// Moves the end by [delta]; a move that breaks a rule is ignored.
  ClipRange nudgeEnd(Duration delta, {required Duration videoDuration}) {
    final moved = copyWith(end: end + delta);
    return moved._fitsIn(videoDuration) ? moved : this;
  }

  bool _fitsIn(Duration videoDuration) =>
      start >= Duration.zero && end <= videoDuration && length >= minimumLength;

  ClipRange copyWith({Duration? start, Duration? end}) {
    return ClipRange(start: start ?? this.start, end: end ?? this.end);
  }

  @override
  bool operator ==(Object other) =>
      other is ClipRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
