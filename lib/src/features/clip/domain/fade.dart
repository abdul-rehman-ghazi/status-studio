import 'dart:math' as math;

import 'package:status_studio/src/features/clip/domain/clip_range.dart';

const _fullFade = Duration(milliseconds: 500);
const _shortClip = Duration(seconds: 2);

/// How long the picture takes to fade in, and again to fade out (spec
/// FR-33): 0.5 s, or a quarter of a clip shorter than 2 s.
Duration fadeLengthFor(ClipRange clip) {
  final length = clip.length;
  if (length < _shortClip) {
    return length ~/ 4;
  }
  return _fullFade;
}

/// The picture's brightness at [clipTime] into a clip [clipLength] long: 0 at
/// both ends, rising and falling in a straight line over [fadeLength], 1 in
/// between (spec FR-33). Android and iOS use the same rule.
double fadeBrightnessAt(
  Duration clipTime,
  Duration clipLength,
  Duration fadeLength,
) {
  final fadeUs = fadeLength.inMicroseconds;
  if (fadeUs <= 0) {
    return 1;
  }
  final fromStart = clipTime.inMicroseconds / fadeUs;
  final toEnd = (clipLength - clipTime).inMicroseconds / fadeUs;
  return math.min(1, math.min(fromStart, toEnd)).clamp(0, 1).toDouble();
}
