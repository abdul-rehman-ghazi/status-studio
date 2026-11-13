import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';

/// What to download for [cut] (spec FR-37): the cut with [margin] on both
/// sides, where the blends play, clamped to the video.
ClipWindow downloadWindowFor(
  TopicCut cut,
  Duration margin,
  Duration videoLength,
) {
  final start = cut.start - margin;
  final end = cut.end + margin;
  return ClipWindow(
    start: start < Duration.zero ? Duration.zero : start,
    end: end > videoLength ? videoLength : end,
  );
}

/// How far a cut plays past its ends to make room for [transition].
Duration marginFor(ClipTransition transition) =>
    transition == ClipTransition.cut ? Duration.zero : transitionLength;
