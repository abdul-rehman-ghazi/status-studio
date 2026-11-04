import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

const _smallestSizeRatio = 0.4;
const _mostFaceWidthsAway = 2.0;

/// Where a face is in a frame, as fractions of the frame (spec FR-23).
@immutable
class SubjectBox {
  const SubjectBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get centreX => left + width / 2;
  double get centreY => top + height / 2;
  double get area => width * height;

  /// Whether [other], a moment later, could be this same face: about the same
  /// size and within two face-widths (and heights) of it. Distance rather than
  /// overlap, because a person who moves quickly leaves no overlap between
  /// frames a quarter of a second apart.
  bool couldBeSameFaceAs(SubjectBox other) {
    if (area <= 0 || other.area <= 0) {
      return false;
    }
    final sizeRatio = other.area / area;
    if (sizeRatio < _smallestSizeRatio || sizeRatio > 1 / _smallestSizeRatio) {
      return false;
    }
    return (other.centreX - centreX).abs() <=
            _mostFaceWidthsAway * math.max(width, other.width) &&
        (other.centreY - centreY).abs() <=
            _mostFaceWidthsAway * math.max(height, other.height);
  }

  @override
  bool operator ==(Object other) =>
      other is SubjectBox &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// The faces found in the frame at [time] (video time); none is an empty list.
@immutable
class SubjectSample {
  const SubjectSample({required this.time, required this.faces});

  final Duration time;
  final List<SubjectBox> faces;
}

/// One person to choose, as a face in one sampled frame (spec FR-25).
///
/// [face] is found in the samples by equality, so it must be the very object
/// from [sampleIndex]'s sample, never rebuilt from screen coordinates.
@immutable
class PersonChoice {
  const PersonChoice({required this.sampleIndex, required this.face});

  /// The frame's place in the whole track's samples.
  final int sampleIndex;
  final SubjectBox face;

  @override
  bool operator ==(Object other) =>
      other is PersonChoice &&
      other.sampleIndex == sampleIndex &&
      other.face == face;

  @override
  int get hashCode => Object.hash(sampleIndex, face);
}

/// What detection found over the clip, in time order (spec FR-23).
@immutable
class SubjectTrack {
  const SubjectTrack({required this.samples, this.sceneCuts});

  final List<SubjectSample> samples;

  /// The scene cuts' video times. None when they are not known (the scene
  /// detector gave nothing usable), which is different from an empty list:
  /// then a big jump of the face stands in for a cut.
  final List<Duration>? sceneCuts;
}

/// The crop window's size in the frame, and where the clip is (spec FR-22).
@immutable
class FollowGeometry {
  const FollowGeometry({
    required this.clip,
    required this.windowWidth,
    required this.windowHeight,
    required this.base,
  });

  /// The window [frame] crops from a [sourceSize] video, as fractions of it.
  /// Throws for Blur and 16:9, which keep the whole frame.
  factory FollowGeometry.forFrame({
    required FrameSettings frame,
    required OutputSize sourceSize,
    required ClipRange clip,
  }) {
    final window = cropRectFor(frame, sourceSize);
    return FollowGeometry(
      clip: clip,
      windowWidth: window.width / sourceSize.width,
      windowHeight: window.height / sourceSize.height,
      base: baseAnchorFor(frame),
    );
  }

  final ClipRange clip;

  /// The window's share of the frame's width and height.
  final double windowWidth;
  final double windowHeight;

  /// Where the crop is now; an axis with no room keeps it.
  final CropAnchor base;

  double get roomX => 1 - windowWidth;
  double get roomY => 1 - windowHeight;
}
