import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

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

  /// Intersection over union with [other], from 0 (apart) to 1 (the same).
  double overlapWith(SubjectBox other) {
    final overlapWidth =
        math.min(left + width, other.left + other.width) -
        math.max(left, other.left);
    final overlapHeight =
        math.min(top + height, other.top + other.height) -
        math.max(top, other.top);
    if (overlapWidth <= 0 || overlapHeight <= 0) {
      return 0;
    }
    final shared = overlapWidth * overlapHeight;
    return shared / (area + other.area - shared);
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
