import 'dart:math' as math;

import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/face_tracks.dart';
import 'package:status_studio/src/features/style/domain/scene_choice.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

const _smallestRoom = 0.01;
const _medianWindow = 5;
const _deadZone = 0.08;
const _tolerance = 0.03;
const _toleranceGrowth = 1.5;
const _mostKeyframes = 12;

/// A clip's first scenes are asked, one cut keyframe each; any later scene
/// holds the last anchor.
const mostScenesFollowed = _mostKeyframes;
const _jumpIsACut = 0.3;
const _keyframeSpacing = Duration(milliseconds: 500);
const _tenth = Duration(milliseconds: 100);

/// A scene's Cut keyframe sits this much before the cut, not on it: the
/// renderer reads a frame's time in whole milliseconds, so a keyframe on the
/// cut could still show the new shot's first frame with the old crop. A frame
/// is longer than this at any frame rate up to 100 fps.
const _cutLead = Duration(milliseconds: 10);

/// The crop path for what the user chose in each scene, in order (spec
/// FR-27): a face or body is followed within its scene, a spot is held.
///
/// [choices] may be fewer than [scenes] (a clip with more than
/// [mostScenesFollowed] scenes); the crop then holds after the last choice.
/// Throws [ArgumentError] when there are more choices than scenes.
CropPath pathForChoices(
  List<SubjectScene> scenes,
  FollowGeometry geometry,
  List<SceneChoice> choices,
) {
  if (choices.length > scenes.length) {
    throw ArgumentError.value(choices.length, 'choices', 'more than scenes');
  }
  final paths = [
    for (final (index, choice) in choices.indexed)
      _scenePoints(scenes[index], geometry, choice),
  ];
  return CropPath(_cappedKeyframes(paths, geometry.clip));
}

/// The crop anchor that puts the spot at ([x], [y]), as fractions of the
/// frame, in the middle of the window.
CropAnchor anchorForSpot(double x, double y, FollowGeometry geometry) {
  return _anchorKeeping(_Aim(x: x, y: y, windowDown: 1 / 2), geometry);
}

// --- Scenes -------------------------------------------------------------

/// A stretch of the clip between cuts, with the samples in it.
class SubjectScene {
  const SubjectScene({
    required this.firstIndex,
    required this.start,
    required this.samples,
  });

  /// Where the scene's first sample is in the whole track's samples.
  final int firstIndex;
  final Duration start;
  final List<SubjectSample> samples;
}

/// The scenes of [track]: split at the detected cuts and at the jumps the
/// detector missed. A stretch with no samples is left out.
List<SubjectScene> scenesOf(SubjectTrack track, FollowGeometry geometry) {
  final cuts = _cutsInsideClip(
    _withMissedJumps(
      track.sceneCuts ?? const [],
      _cutsFromJumps(track.samples, geometry),
    ),
    geometry.clip,
  );
  return _scenesBetween(track.samples, cuts, geometry.clip);
}

/// The cuts that make a scene long enough to hold its keyframe: one within
/// half a second of the scene before it, or of the clip's end, is not a
/// boundary, or the user's answer for that scene would be dropped by the
/// keyframe spacing. A cut is compared as its keyframe will be (a little
/// before it, see [_cutLead]), and the clip's ends as theirs are (rounded
/// inwards to a tenth of a second).
List<Duration> _cutsInsideClip(List<Duration> cuts, ClipRange clip) {
  final inside =
      cuts.where((cut) => cut > clip.start && cut < clip.end).toList()..sort();
  final kept = <Duration>[];
  var previous = _roundedUpToTenth(clip.start);
  final latest = _roundedDownToTenth(clip.end);
  for (final cut in inside) {
    final at = cut - _cutLead;
    final longEnough =
        at - previous >= _keyframeSpacing && latest - at >= _keyframeSpacing;
    if (longEnough) {
      kept.add(cut);
      previous = at;
    }
  }
  return kept;
}

List<SubjectScene> _scenesBetween(
  List<SubjectSample> samples,
  List<Duration> cuts,
  ClipRange clip,
) {
  final starts = [clip.start, ...cuts];
  final scenes = <SubjectScene>[];
  for (final (index, start) in starts.indexed) {
    final end = index + 1 < starts.length ? starts[index + 1] : null;
    bool isInScene(SubjectSample sample) =>
        sample.time >= start && (end == null || sample.time < end);
    final firstIndex = samples.indexWhere(isInScene);
    if (firstIndex >= 0) {
      scenes.add(
        SubjectScene(
          firstIndex: firstIndex,
          start: start,
          samples: samples.where(isInScene).toList(),
        ),
      );
    }
  }
  return scenes;
}

/// The detected cuts, and any jump the detector missed (a soft cut): one
/// that is not within a keyframe's spacing of a detected cut.
List<Duration> _withMissedJumps(List<Duration> detected, List<Duration> jumps) {
  final missed = jumps.where(
    (jump) => !detected.any((cut) => (cut - jump).abs() < _keyframeSpacing),
  );
  return [...detected, ...missed];
}

/// Where no face of a frame is a face of the frame before, and the picture's
/// centre of attention jumps far: a cut, whether or not the scene detector
/// saw one. A bystander coming or going does not count, since the followed
/// person is still there; nor does a person missed for a moment.
List<Duration> _cutsFromJumps(
  List<SubjectSample> samples,
  FollowGeometry geometry,
) {
  final cuts = <Duration>[];
  for (var i = 1; i < samples.length; i++) {
    final before = samples[i - 1].faces;
    final after = samples[i].faces;
    if (before.isEmpty || after.isEmpty || _someFaceContinues(before, after)) {
      continue;
    }
    if (_seenAroundTheBreak(samples, i)) {
      continue;
    }
    final jump = _distanceBetween(
      _anchorFor(_largest(before), geometry),
      _anchorFor(_largest(after), geometry),
    );
    if (jump > _jumpIsACut) {
      cuts.add(samples[i].time);
    }
  }
  return cuts;
}

bool _someFaceContinues(List<SubjectBox> before, List<SubjectBox> after) {
  return after.any((face) => before.any((b) => b.couldBeSameFaceAs(face)));
}

/// A face from before [breakIndex] is back within two seconds, or one after
/// it was there that recently: the person was only missed for a moment, or
/// someone stood in front. The picture did not cut.
bool _seenAroundTheBreak(List<SubjectSample> samples, int breakIndex) {
  final before = samples[breakIndex - 1];
  final after = samples[breakIndex];
  for (var i = breakIndex + 1; i < samples.length; i++) {
    if (samples[i].time - before.time > longestFaceGap) {
      break;
    }
    if (_someFaceContinues(before.faces, samples[i].faces)) {
      return true;
    }
  }
  for (var i = breakIndex - 2; i >= 0; i--) {
    if (after.time - samples[i].time > longestFaceGap) {
      break;
    }
    if (_someFaceContinues(samples[i].faces, after.faces)) {
      return true;
    }
  }
  return false;
}

SubjectBox _largest(List<SubjectBox> faces) =>
    faces.reduce((best, next) => next.area > best.area ? next : best);

double _distanceBetween(CropAnchor from, CropAnchor to) =>
    math.max((to.x - from.x).abs(), (to.y - from.y).abs());

// --- One scene's anchors ------------------------------------------------

class _Point {
  const _Point(this.time, this.anchor);

  final Duration time;
  final CropAnchor anchor;
}

List<_Point> _scenePoints(
  SubjectScene scene,
  FollowGeometry geometry,
  SceneChoice choice,
) {
  return switch (choice) {
    // A spot is a cut to where the user pointed, and no move after it.
    HoldSpot(:final anchor) => [_Point(scene.start, anchor)],
    FollowFace(:final track) => _followedPoints(
      scene,
      geometry,
      _Followed(track, _anchorFor),
    ),
    FollowBody(:final track) => _followedPoints(
      scene,
      geometry,
      _Followed(track, _bodyAnchorFor),
    ),
  };
}

/// Who is followed in a scene, and how a box of theirs becomes an anchor.
class _Followed {
  const _Followed(this.track, this.anchorFor);

  final FaceTrack track;
  final CropAnchor Function(SubjectBox box, FollowGeometry geometry) anchorFor;
}

List<_Point> _followedPoints(
  SubjectScene scene,
  FollowGeometry geometry,
  _Followed followed,
) {
  final anchors = _filledAnchors(scene.samples, geometry, followed);
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

/// The anchor for every sample: a frame where the followed one is not seen
/// holds the last anchor, and the frames before the first sighting take that
/// one.
List<CropAnchor> _filledAnchors(
  List<SubjectSample> samples,
  FollowGeometry geometry,
  _Followed followed,
) {
  final found = <CropAnchor?>[];
  for (var i = 0; i < samples.length; i++) {
    final box = followed.track.faceAt(i);
    found.add(box == null ? null : followed.anchorFor(box, geometry));
  }
  final first = found.firstWhere((a) => a != null, orElse: () => null);
  var held = first ?? geometry.base;
  return [for (final anchor in found) held = anchor ?? held];
}

/// The window centred on the face across, with the face a third of the way
/// down it; an axis with almost no room keeps the base.
CropAnchor _anchorFor(SubjectBox face, FollowGeometry geometry) {
  return _anchorKeeping(
    _Aim(x: face.centreX, y: face.centreY, windowDown: 1 / 3),
    geometry,
  );
}

/// The window centred on the body across, with the body's upper third (where
/// the head and chest are) a third of the way down the window.
CropAnchor _bodyAnchorFor(SubjectBox body, FollowGeometry geometry) {
  return _anchorKeeping(
    _Aim(x: body.centreX, y: body.top + body.height / 3, windowDown: 1 / 3),
    geometry,
  );
}

/// A point of the frame and how far down the window it should sit.
class _Aim {
  const _Aim({required this.x, required this.y, required this.windowDown});

  final double x;
  final double y;
  final double windowDown;
}

/// The anchor that puts [aim]'s point where it says in the window; an axis
/// with almost no room keeps the base.
CropAnchor _anchorKeeping(_Aim aim, FollowGeometry geometry) {
  final anchorX = geometry.roomX < _smallestRoom
      ? geometry.base.x
      : (aim.x - geometry.windowWidth / 2) / geometry.roomX;
  final anchorY = geometry.roomY < _smallestRoom
      ? geometry.base.y
      : (aim.y - geometry.windowHeight * aim.windowDown) / geometry.roomY;
  return CropAnchor(x: anchorX, y: anchorY).clamped();
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
  return _mergedDownToTheMost(keyframes);
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

/// Many scenes can leave more keyframes than any tolerance removes, so the
/// ones that change the crop least go, wherever they are: the end of the clip
/// is never simply cut off. A cut is the user's choice for its scene, so a
/// glide goes before any cut does. The first keyframe stays.
List<CropKeyframe> _mergedDownToTheMost(List<CropKeyframe> keyframes) {
  final kept = [...keyframes];
  while (kept.length > _mostKeyframes) {
    kept.removeAt(_leastChangingIndex(kept));
  }
  return kept;
}

int _leastChangingIndex(List<CropKeyframe> keyframes) {
  final glides = [
    for (var i = 1; i < keyframes.length; i++)
      if (keyframes[i].arrival == CropArrival.glide) i,
  ];
  final candidates = glides.isNotEmpty
      ? glides
      : [for (var i = 1; i < keyframes.length; i++) i];
  return candidates.reduce(
    (best, next) =>
        _changeAt(keyframes, next) < _changeAt(keyframes, best) ? next : best,
  );
}

double _changeAt(List<CropKeyframe> keyframes, int index) => math.max(
  (keyframes[index].anchor.x - keyframes[index - 1].anchor.x).abs(),
  (keyframes[index].anchor.y - keyframes[index - 1].anchor.y).abs(),
);

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
      final time = _within(
        startsScene ? point.time - _cutLead : _snapped(point.time),
        earliest,
        latest,
      );
      final keyframe = CropKeyframe(
        time: keyframes.isEmpty ? earliest : time,
        anchor: point.anchor,
        arrival: startsScene ? CropArrival.cut : CropArrival.glide,
      );
      _addWithSpacing(keyframes, keyframe, latest);
    }
  }
  return keyframes;
}

/// Keyframes closer than half a second to the one before are dropped, unless
/// the new one is a cut, which replaces the one before it instead, or a move
/// the dead zone would not hide (see [_addAfterThePause]).
void _addWithSpacing(
  List<CropKeyframe> keyframes,
  CropKeyframe next,
  Duration latest,
) {
  if (keyframes.isEmpty) {
    keyframes.add(next);
    return;
  }
  if (next.time - keyframes.last.time >= _keyframeSpacing) {
    keyframes.add(next);
    return;
  }
  if (next.arrival != CropArrival.cut) {
    _addAfterThePause(keyframes, next, latest);
    return;
  }
  if (keyframes.length > 1) {
    keyframes
      ..removeLast()
      ..add(next);
    return;
  }
  // The only keyframe so far is the clip's start: the cut came right after
  // it, so the start takes the new shot's anchor and keeps its time.
  keyframes[0] = keyframes[0].copyWith(anchor: next.anchor);
}

/// A big move right after a hold (the person was missed for a while and is
/// back elsewhere) is the one thing that must not be dropped, or the crop
/// would never leave the old place. It starts the hold's half second later.
void _addAfterThePause(
  List<CropKeyframe> keyframes,
  CropKeyframe next,
  Duration latest,
) {
  final previous = keyframes.last;
  final moved = _distanceBetween(previous.anchor, next.anchor);
  final arrives = previous.time + _keyframeSpacing;
  if (moved <= _deadZone || arrives > latest) {
    return;
  }
  keyframes.add(next.copyWith(time: arrives));
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
