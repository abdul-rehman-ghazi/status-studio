import 'dart:math' as math;

import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

const _sameFaceOverlap = 0.3;
const _smallestRoom = 0.01;
const _medianWindow = 5;
const _deadZone = 0.08;
const _tolerance = 0.03;
const _toleranceGrowth = 1.5;
const _mostKeyframes = 12;
const _jumpIsACut = 0.3;
const _leastFaceShare = 0.2;
const _leastFaceFrames = 3;
const _keyframeSpacing = Duration(milliseconds: 500);
const _tenth = Duration(milliseconds: 100);

/// The crop path that follows the person in [track] (spec FR-23).
///
/// Throws [NoSubjectFoundException] when faces are too rare to follow.
CropPath followSubject(SubjectTrack track, FollowGeometry geometry) {
  _requireEnoughFaces(track.samples);
  final cuts = _cutsInsideClip(
    track.sceneCuts ?? _cutsFromJumps(track.samples, geometry),
    geometry.clip,
  );
  final scenes = _scenesOf(track.samples, cuts, geometry.clip);
  final paths = [for (final scene in scenes) _scenePoints(scene, geometry)];
  return CropPath(_cappedKeyframes(paths, geometry.clip));
}

void _requireEnoughFaces(List<SubjectSample> samples) {
  final withFaces = samples.where((sample) => sample.faces.isNotEmpty).length;
  final share = samples.isEmpty ? 0 : withFaces / samples.length;
  if (withFaces < _leastFaceFrames || share < _leastFaceShare) {
    throw const NoSubjectFoundException();
  }
}

// --- Scenes -------------------------------------------------------------

class _Scene {
  const _Scene({required this.start, required this.samples});

  final Duration start;
  final List<SubjectSample> samples;
}

List<Duration> _cutsInsideClip(List<Duration> cuts, ClipRange clip) {
  return cuts.where((cut) => cut > clip.start && cut < clip.end).toList()
    ..sort();
}

List<_Scene> _scenesOf(
  List<SubjectSample> samples,
  List<Duration> cuts,
  ClipRange clip,
) {
  final starts = [clip.start, ...cuts];
  final scenes = <_Scene>[];
  for (final (index, start) in starts.indexed) {
    final end = index + 1 < starts.length ? starts[index + 1] : null;
    final inScene = samples
        .where(
          (sample) =>
              sample.time >= start && (end == null || sample.time < end),
        )
        .toList();
    if (inScene.isNotEmpty) {
      scenes.add(_Scene(start: start, samples: inScene));
    }
  }
  return scenes;
}

/// With no scene-cut data, a face that jumps far between two neighbouring
/// frames is taken to be a cut.
List<Duration> _cutsFromJumps(
  List<SubjectSample> samples,
  FollowGeometry geometry,
) {
  final cuts = <Duration>[];
  SubjectBox? previousFace;
  CropAnchor? previousAnchor;
  for (final sample in samples) {
    final face = _pickFace(sample.faces, previousFace);
    if (face == null) {
      previousFace = null;
      previousAnchor = null;
      continue;
    }
    final anchor = _anchorFor(face, geometry);
    final before = previousAnchor;
    if (before != null &&
        math.max((anchor.x - before.x).abs(), (anchor.y - before.y).abs()) >
            _jumpIsACut) {
      cuts.add(sample.time);
    }
    previousFace = face;
    previousAnchor = anchor;
  }
  return cuts;
}

// --- One scene's anchors ------------------------------------------------

class _Point {
  const _Point(this.time, this.anchor);

  final Duration time;
  final CropAnchor anchor;
}

List<_Point> _scenePoints(_Scene scene, FollowGeometry geometry) {
  final anchors = _filledAnchors(scene.samples, geometry);
  final xs = _followedWithDeadZone(_median([for (final a in anchors) a.x]));
  final ys = _followedWithDeadZone(_median([for (final a in anchors) a.y]));
  final points = [
    for (final (index, sample) in scene.samples.indexed)
      _Point(
        // The scene's first point sits at the cut itself.
        index == 0 ? scene.start : sample.time,
        CropAnchor(x: xs[index], y: ys[index]),
      ),
  ];
  return _simplified(points, _tolerance);
}

/// The anchor for every sample: a frame with no face holds the last one;
/// the frames before the first face take that face's; a scene with no face
/// keeps the base.
List<CropAnchor> _filledAnchors(
  List<SubjectSample> samples,
  FollowGeometry geometry,
) {
  final found = <CropAnchor?>[];
  SubjectBox? previousFace;
  for (final sample in samples) {
    final face = _pickFace(sample.faces, previousFace);
    found.add(face == null ? null : _anchorFor(face, geometry));
    previousFace = face ?? previousFace;
  }
  final first = found.firstWhere((a) => a != null, orElse: () => null);
  var held = first ?? geometry.base;
  return [for (final anchor in found) held = anchor ?? held];
}

/// The face to follow: the one that overlaps the previous pick, else the
/// largest.
SubjectBox? _pickFace(List<SubjectBox> faces, SubjectBox? previous) {
  if (faces.isEmpty) {
    return null;
  }
  if (previous != null) {
    final closest = faces.reduce(
      (best, next) =>
          next.overlapWith(previous) > best.overlapWith(previous) ? next : best,
    );
    if (closest.overlapWith(previous) >= _sameFaceOverlap) {
      return closest;
    }
  }
  return faces.reduce((best, next) => next.area > best.area ? next : best);
}

/// The window centred on the face across, with the face a third of the way
/// down it; an axis with almost no room keeps the base.
CropAnchor _anchorFor(SubjectBox face, FollowGeometry geometry) {
  final x = geometry.roomX < _smallestRoom
      ? geometry.base.x
      : (face.centreX - geometry.windowWidth / 2) / geometry.roomX;
  final y = geometry.roomY < _smallestRoom
      ? geometry.base.y
      : (face.centreY - geometry.windowHeight / 3) / geometry.roomY;
  return CropAnchor(x: x, y: y).clamped();
}

List<double> _median(List<double> values) {
  return [
    for (var i = 0; i < values.length; i++)
      _middleOf(
        values.sublist(
          math.max(0, i - _medianWindow ~/ 2),
          math.min(values.length, i + _medianWindow ~/ 2 + 1),
        ),
      ),
  ];
}

double _middleOf(List<double> window) {
  final sorted = [...window]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Holds still while the target stays within the dead zone; past it, moves
/// just enough to stay that far behind, so a steady drift is a straight line
/// and a small sway is nothing.
List<double> _followedWithDeadZone(List<double> targets) {
  var held = targets.first;
  return [
    for (final target in targets)
      held += (target - held).abs() > _deadZone
          ? (target - held) - _deadZone * (target - held).sign
          : 0,
  ];
}

// --- Fewer keyframes ------------------------------------------------------

/// Ramer–Douglas–Peucker on the anchor over time: points that a straight
/// glide between their neighbours would reproduce within [epsilon] go.
List<_Point> _simplified(List<_Point> points, double epsilon) {
  if (points.length <= 2) {
    return points;
  }
  var worst = 0.0;
  var worstIndex = 0;
  final first = points.first;
  final last = points.last;
  for (var i = 1; i < points.length - 1; i++) {
    final error = _distanceFromGlide(points[i], first, last);
    if (error > worst) {
      worst = error;
      worstIndex = i;
    }
  }
  if (worst <= epsilon) {
    return [first, last];
  }
  final before = _simplified(points.sublist(0, worstIndex + 1), epsilon);
  final after = _simplified(points.sublist(worstIndex), epsilon);
  return [...before, ...after.skip(1)];
}

double _distanceFromGlide(_Point point, _Point from, _Point to) {
  final span = (to.time - from.time).inMicroseconds;
  final fraction = span == 0
      ? 0.0
      : (point.time - from.time).inMicroseconds / span;
  final onGlide = from.anchor.towards(to.anchor, fraction);
  return math.max(
    (point.anchor.x - onGlide.x).abs(),
    (point.anchor.y - onGlide.y).abs(),
  );
}

/// Keyframes for every scene, with the tolerance grown until there are at
/// most [_mostKeyframes]; a scene's first keyframe is a Cut, since the
/// picture jumped there.
List<CropKeyframe> _cappedKeyframes(
  List<List<_Point>> scenePaths,
  ClipRange clip,
) {
  var tolerance = _tolerance;
  List<CropKeyframe> keyframes;
  var attempts = 0;
  do {
    keyframes = _keyframesFrom([
      for (final path in scenePaths)
        _withoutIdleEnd(_simplified(path, tolerance), tolerance),
    ], clip);
    tolerance *= _toleranceGrowth;
    attempts++;
  } while (keyframes.length > _mostKeyframes && attempts < 20);
  return keyframes.take(_mostKeyframes).toList();
}

/// A scene's last point that sits where the one before it is adds nothing:
/// after it the crop holds (or a cut comes), so the hold is the same.
List<_Point> _withoutIdleEnd(List<_Point> points, double tolerance) {
  if (points.length < 2) {
    return points;
  }
  final last = points.last;
  final before = points[points.length - 2];
  final moved = math.max(
    (last.anchor.x - before.anchor.x).abs(),
    (last.anchor.y - before.anchor.y).abs(),
  );
  return moved <= tolerance ? points.sublist(0, points.length - 1) : points;
}

List<CropKeyframe> _keyframesFrom(
  List<List<_Point>> scenePaths,
  ClipRange clip,
) {
  final earliest = _roundedUpToTenth(clip.start);
  final latest = _roundedDownToTenth(clip.end);
  final keyframes = <CropKeyframe>[];
  for (final (sceneIndex, path) in scenePaths.indexed) {
    for (final (pointIndex, point) in path.indexed) {
      final startsScene = pointIndex == 0 && sceneIndex > 0;
      final time = _within(_snapped(point.time), earliest, latest);
      final keyframe = CropKeyframe(
        time: keyframes.isEmpty ? earliest : time,
        anchor: point.anchor,
        arrival: startsScene ? CropArrival.cut : CropArrival.glide,
      );
      _addWithSpacing(keyframes, keyframe);
    }
  }
  return keyframes;
}

/// Keyframes closer than half a second to the one before are dropped, unless
/// the new one is a cut, which replaces the one before it instead.
void _addWithSpacing(List<CropKeyframe> keyframes, CropKeyframe next) {
  if (keyframes.isEmpty) {
    keyframes.add(next);
    return;
  }
  if (next.time - keyframes.last.time >= _keyframeSpacing) {
    keyframes.add(next);
    return;
  }
  if (next.arrival == CropArrival.cut && keyframes.length > 1) {
    keyframes
      ..removeLast()
      ..add(next);
  }
}

Duration _snapped(Duration time) =>
    _tenth * (time.inMicroseconds / _tenth.inMicroseconds).round();

Duration _roundedUpToTenth(Duration time) =>
    _tenth * (time.inMicroseconds / _tenth.inMicroseconds).ceil();

Duration _roundedDownToTenth(Duration time) =>
    _tenth * (time.inMicroseconds / _tenth.inMicroseconds).floor();

Duration _within(Duration time, Duration earliest, Duration latest) {
  if (time < earliest) {
    return earliest;
  }
  return time > latest ? latest : time;
}
