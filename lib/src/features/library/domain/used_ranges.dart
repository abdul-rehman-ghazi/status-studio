import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/join/domain/linked_clip.dart';

/// A stretch of the source video a reel used (spec FR-44): of the local
/// video, or of the YouTube video for a joined link clip.
@immutable
class SourceRange {
  const SourceRange({required this.start, required this.end});

  /// Throws [FormatException] for a JSON that isn't a source range.
  factory SourceRange.fromJson(Object? json) => switch (json) {
    {'startMs': final int startMs, 'endMs': final int endMs} => SourceRange(
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    ),
    _ => throw const FormatException('Not a source range.'),
  };

  final Duration start;
  final Duration end;

  /// Touching only at an edge is no overlap.
  bool overlaps(Duration otherStart, Duration otherEnd) =>
      start < otherEnd && otherStart < end;

  Map<String, Object?> toJson() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is SourceRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// What a reel of [clip] used of its source (spec FR-44): the clip itself
/// for a local video; for a joined link clip, each cut's part inside the
/// trim, mapped back to the YouTube video, in source order. Empty for a
/// clip joined before M54, which kept no cut times.
List<SourceRange> usedRangesFor(ClipRange clip, LinkedClip? linked) {
  if (linked == null) {
    return [SourceRange(start: clip.start, end: clip.end)];
  }
  final ranges = [
    for (final cut in linked.cuts)
      if (cut.joinedStart < clip.end && clip.start < cut.joinedEnd)
        SourceRange(
          start:
              cut.sourceStart +
              _later(clip.start, cut.joinedStart) -
              cut.joinedStart,
          end:
              cut.sourceStart +
              _sooner(clip.end, cut.joinedEnd) -
              cut.joinedStart,
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return ranges;
}

Duration _later(Duration a, Duration b) => a > b ? a : b;

Duration _sooner(Duration a, Duration b) => a < b ? a : b;
