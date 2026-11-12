import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/join/domain/cut_window.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';

/// A ticked cut and the file it was downloaded into.
@immutable
class DownloadedCut {
  const DownloadedCut({required this.cut, required this.file});

  final TopicCut cut;
  final CutFile file;
}

/// One stretch of a cut file played in a layer of the join, with how long
/// its sound fades at one end. Positions are in the file's own time.
@immutable
class JoinItem {
  const JoinItem({
    required this.path,
    required this.start,
    required this.end,
    required this.blend,
  });

  final String path;
  final Duration start;
  final Duration end;

  /// The upper layer's items blend out over their last [blend]; the lower
  /// layer's items are leads, [blend] long, blending in.
  final Duration blend;

  Duration get length => end - start;

  Map<String, Object?> toChannel() => {
    'path': path,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'blendMs': blend.inMilliseconds,
  };
}

/// When a transition plays in the joined clip's time.
@immutable
class TransitionWindow {
  const TransitionWindow({required this.start, required this.end});

  final Duration start;
  final Duration end;

  /// Where the crop changes (spec FR-37).
  Duration get middle => start + (end - start) ~/ 2;

  Map<String, Object?> toChannel() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };
}

/// What the native joiner plays (spec FR-37): two layers. The upper plays
/// each cut with its tail, without gaps; the lower only each cut's lead, at
/// its window, so a second decoder runs only around the joins (a phone may
/// have one hardware decoder's worth of 1080p60). Inside a window the upper
/// gives way to the lower, so the blend sits in the margins and no word of
/// a cut is faded.
@immutable
class JoinPlan {
  const JoinPlan({
    required this.transition,
    required this.upper,
    required this.lower,
    required this.windows,
    required this.joinTimes,
    required this.length,
  });

  final ClipTransition transition;
  final List<JoinItem> upper;

  /// One lead for each of [windows], in order; empty when no join blends
  /// (Cut, or margins cut short to nothing).
  final List<JoinItem> lower;
  final List<TransitionWindow> windows;

  /// Where each cut gives way to the next, in the joined clip's time: the
  /// middle of its transition. These are scene edges for the crop.
  final List<Duration> joinTimes;
  final Duration length;

  Map<String, Object?> toChannel(String outputPath) => {
    'outputPath': outputPath,
    'transition': transition.name,
    'upper': [for (final item in upper) item.toChannel()],
    'lower': [for (final item in lower) item.toChannel()],
    'windows': [for (final window in windows) window.toChannel()],
    'lengthMs': length.inMilliseconds,
  };
}

/// Lays [cuts] out in their order with [transition] between them.
JoinPlan planJoin(List<DownloadedCut> cuts, ClipTransition transition) {
  final blends = _blendsBetween(cuts, marginFor(transition));
  final upper = <JoinItem>[];
  final lower = <JoinItem>[];
  final windows = <TransitionWindow>[];
  final joinTimes = <Duration>[];
  var cutStart = Duration.zero;
  for (final (index, downloaded) in cuts.indexed) {
    final lead = index == 0 ? Duration.zero : blends[index - 1];
    final tail = index == cuts.length - 1 ? Duration.zero : blends[index];
    if (index > 0) {
      cutStart += lead;
      joinTimes.add(cutStart - lead ~/ 2);
    }
    if (lead > Duration.zero) {
      windows.add(TransitionWindow(start: cutStart - lead, end: cutStart));
      lower.add(_lead(downloaded, lead));
    }
    upper.add(_withTail(downloaded, tail));
    cutStart += downloaded.cut.length;
  }
  return JoinPlan(
    transition: transition,
    upper: upper,
    lower: lower,
    windows: windows,
    joinTimes: joinTimes,
    length: cutStart,
  );
}

/// Each join's blend: the margin, shortened where the outgoing cut's file
/// ends sooner after it or the incoming one's starts later before it (at
/// the video's ends).
List<Duration> _blendsBetween(List<DownloadedCut> cuts, Duration margin) => [
  for (var index = 1; index < cuts.length; index++)
    _shortest([
      margin,
      cuts[index - 1].file.covered.end - cuts[index - 1].cut.end,
      cuts[index].cut.start - cuts[index].file.covered.start,
    ]),
];

Duration _shortest(List<Duration> lengths) {
  final shortest = lengths.reduce((a, b) => a < b ? a : b);
  return shortest < Duration.zero ? Duration.zero : shortest;
}

/// The cut and [tail] after it; it blends out over the tail.
JoinItem _withTail(DownloadedCut downloaded, Duration tail) {
  final file = downloaded.file;
  return JoinItem(
    path: file.file.path,
    start: file.positionOf(downloaded.cut.start),
    end: file.positionOf(downloaded.cut.end + tail),
    blend: tail,
  );
}

/// The [lead] before the cut, all of it blending in.
JoinItem _lead(DownloadedCut downloaded, Duration lead) {
  final file = downloaded.file;
  return JoinItem(
    path: file.file.path,
    start: file.positionOf(downloaded.cut.start - lead),
    end: file.positionOf(downloaded.cut.start),
    blend: lead,
  );
}
