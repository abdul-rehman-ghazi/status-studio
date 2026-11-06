import 'package:status_studio/src/features/style/domain/crop_path.dart';

/// How far either side of a cut the preview dims (spec FR-21, FR-22).
const _dipHalfWidth = Duration(milliseconds: 100);

/// The picture's dimmest point, on the cut itself.
const _dipFloor = 0.35;

/// The opacity the playing preview gives the video at [time]: it dips around
/// each Cut keyframe and is 1 elsewhere.
///
/// The player reports its position only about twice a second, so while
/// playing the preview's crop can be a few milliseconds off the picture it
/// sits on; a cut then shows as a one-frame jerk. The dip hides that. The
/// export reads each frame's own time and cuts exactly, so it has no dip.
double opacityAroundCuts(CropPath path, Duration time) {
  var opacity = 1.0;
  for (final keyframe in path.keyframes) {
    if (keyframe.arrival != CropArrival.cut) {
      continue;
    }
    final away = (time - keyframe.shownAt).abs();
    if (away >= _dipHalfWidth) {
      continue;
    }
    final here =
        _dipFloor +
        (1 - _dipFloor) * away.inMicroseconds / _dipHalfWidth.inMicroseconds;
    opacity = opacity < here ? opacity : here;
  }
  return opacity;
}
