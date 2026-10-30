import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';

const _padding = Duration(seconds: 5);
const _minimumLength = Duration(seconds: 30);

/// The stretch of video downloaded around a clip, in video time (FR-15).
@immutable
class ClipWindow {
  const ClipWindow({required this.start, required this.end});

  final Duration start;
  final Duration end;

  bool covers(ClipRange clip) => start <= clip.start && clip.end <= end;

  @override
  bool operator ==(Object other) =>
      other is ClipWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ClipWindow($start, $end)';
}

/// From 5 s before the clip to 5 s after it, and at least 30 s long, so
/// small nudges reuse the download; clamped to the video.
ClipWindow clipWindowFor(ClipRange clip, Duration videoDuration) {
  final paddedEnd = clip.end + _padding;
  final minimumEnd = clip.start + _minimumLength;
  final end = paddedEnd > minimumEnd ? paddedEnd : minimumEnd;
  final start = clip.start - _padding;
  return ClipWindow(
    start: start < Duration.zero ? Duration.zero : start,
    end: end > videoDuration ? videoDuration : end,
  );
}
