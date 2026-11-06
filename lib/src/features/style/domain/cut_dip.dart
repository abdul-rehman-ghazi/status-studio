import 'dart:math' as math;

import 'package:status_studio/src/features/style/domain/crop_path.dart';

/// How far either side of a cut the picture dims (spec FR-22). The Android
/// renderer's `CutDip.kt` has the same numbers.
const _dipHalfWidth = Duration(milliseconds: 160);

/// The picture's dimmest point, on the cut itself.
const _dipFloor = 0.4;

/// How bright the picture is at [time]: [_dipFloor] on each scene cut,
/// easing back to 1 along a cosine over [_dipHalfWidth] either side, so there
/// is no corner at the cut or where the dip ends. 1 away from every cut.
///
/// The export applies it to every frame; the playing preview applies it too,
/// which also hides that its crop is read from an estimated playhead and can
/// sit a few milliseconds off the picture at a cut. The first keyframe has
/// no shot before it, so it never dips.
double opacityAroundCuts(CropPath path, Duration time) {
  var opacity = 1.0;
  for (final keyframe in path.keyframes.skip(1)) {
    if (keyframe.arrival != CropArrival.cut) {
      continue;
    }
    final away = (time - keyframe.shownAt).abs();
    if (away >= _dipHalfWidth) {
      continue;
    }
    final here = _brightnessAway(
      away.inMicroseconds / _dipHalfWidth.inMicroseconds,
    );
    opacity = math.min(opacity, here);
  }
  return opacity;
}

/// [shareOfHalfWidth] is 0 on the cut and 1 at the dip's edge.
double _brightnessAway(double shareOfHalfWidth) {
  final eased = (1 - math.cos(math.pi * shareOfHalfWidth)) / 2;
  return _dipFloor + (1 - _dipFloor) * eased;
}
