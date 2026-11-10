import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';

const _snap = Duration(milliseconds: 100);
const _replaceWithin = Duration(milliseconds: 250);

/// Where a crop window sits in the room it has to move (spec FR-22): each
/// of [x] and [y] runs from 0 (left or top) to 1 (right or bottom).
@immutable
class CropAnchor {
  const CropAnchor({required this.x, required this.y});

  final double x;
  final double y;

  CropAnchor clamped() =>
      CropAnchor(x: x.clamp(0, 1).toDouble(), y: y.clamp(0, 1).toDouble());

  CropAnchor towards(CropAnchor other, double fraction) {
    return CropAnchor(
      x: x + (other.x - x) * fraction,
      y: y + (other.y - y) * fraction,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropAnchor && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CropAnchor($x, $y)';
}

/// How a keyframe is reached from the one before it.
enum CropArrival { glide, cut }

/// A scene's Cut keyframe sits this much before the cut (spec FR-27): the
/// renderer reads a frame's time in whole milliseconds, so a keyframe on the
/// cut could still show the new shot's first frame with the old crop. A frame
/// is longer than this at any frame rate below 100 fps.
const cutKeyframeLead = Duration(milliseconds: 10);

/// A crop anchor at a moment of the video, in video time (spec FR-22).
@immutable
class CropKeyframe {
  const CropKeyframe({
    required this.time,
    required this.anchor,
    required this.arrival,
  });

  final Duration time;
  final CropAnchor anchor;
  final CropArrival arrival;

  /// Where to put the playhead to see this keyframe's crop on its own shot: a
  /// Cut's keyframe is [cutKeyframeLead] before the cut, on the old shot.
  Duration get shownAt =>
      arrival == CropArrival.cut ? time + cutKeyframeLead : time;

  CropKeyframe copyWith({
    Duration? time,
    CropAnchor? anchor,
    CropArrival? arrival,
  }) {
    return CropKeyframe(
      time: time ?? this.time,
      anchor: anchor ?? this.anchor,
      arrival: arrival ?? this.arrival,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropKeyframe &&
      other.time == time &&
      other.anchor == anchor &&
      other.arrival == arrival;

  @override
  int get hashCode => Object.hash(time, anchor, arrival);
}

/// The crop window's position over time (spec FR-22). No keyframes means a
/// fixed crop.
@immutable
class CropPath {
  const CropPath([this.keyframes = const []]);

  /// A path that starts with one keyframe, which is how moving the crop
  /// begins.
  factory CropPath.startingAt(Duration time, CropAnchor anchor) => CropPath([
    CropKeyframe(time: time, anchor: anchor, arrival: CropArrival.glide),
  ]);

  /// In time order.
  final List<CropKeyframe> keyframes;

  bool get isEmpty => keyframes.isEmpty;

  /// The anchor at [time]; [base] when there are no keyframes.
  CropAnchor anchorAt(Duration time, {required CropAnchor base}) {
    if (keyframes.isEmpty) {
      return base;
    }
    final next = keyframes.indexWhere((keyframe) => keyframe.time > time);
    if (next < 0) {
      return keyframes.last.anchor;
    }
    if (next == 0) {
      return keyframes.first.anchor;
    }
    return _between(keyframes[next - 1], keyframes[next], time);
  }

  /// Sets the anchor at [time], snapped to a tenth of a second. A keyframe
  /// within a quarter second is replaced and keeps how it arrives; any other
  /// is added and glides in.
  CropPath withAnchorAt(Duration time, CropAnchor anchor) {
    final snapped = _snapped(time);
    final clamped = anchor.clamped();
    final replaced = keyframes.indexWhere(
      (keyframe) => (keyframe.time - snapped).abs() <= _replaceWithin,
    );
    if (replaced >= 0) {
      return _replacing(
        replaced,
        keyframes[replaced].copyWith(anchor: clamped),
      );
    }
    final added = CropKeyframe(
      time: snapped,
      anchor: clamped,
      arrival: CropArrival.glide,
    );
    return CropPath([...keyframes, added]..sort(_byTime));
  }

  /// How long each keyframe's position lasts inside [clip], in time order,
  /// for the scene strip (spec FR-22). The first span starts at the clip
  /// start with the keyframe in force there, even one before the clip;
  /// keyframes after the clip end have no span.
  List<CropSpan> spansIn(ClipRange clip) {
    if (keyframes.isEmpty) {
      return const [];
    }
    final inForce = keyframes.lastIndexWhere(
      (keyframe) => keyframe.time <= clip.start,
    );
    final first = inForce < 0 ? 0 : inForce;
    final spans = <CropSpan>[];
    for (var index = first; index < keyframes.length; index++) {
      final start = index == first ? clip.start : keyframes[index].time;
      if (start >= clip.end) {
        break;
      }
      final isLast = index + 1 == keyframes.length;
      final nextTime = isLast ? clip.end : keyframes[index + 1].time;
      spans.add(
        CropSpan(
          keyframeIndex: index,
          start: start,
          end: nextTime < clip.end ? nextTime : clip.end,
          arrival: keyframes[index].arrival,
        ),
      );
    }
    return spans;
  }

  CropPath withArrival(int index, CropArrival arrival) =>
      _replacing(index, keyframes[index].copyWith(arrival: arrival));

  /// Throws for the only keyframe, which gives the crop its place; turning
  /// the movement off removes them all.
  CropPath withoutKeyframe(int index) {
    if (keyframes.length == 1) {
      throw StateError('The only crop keyframe cannot be removed.');
    }
    return CropPath([...keyframes]..removeAt(index));
  }

  CropPath _replacing(int index, CropKeyframe keyframe) {
    return CropPath([...keyframes]..[index] = keyframe);
  }

  @override
  bool operator ==(Object other) =>
      other is CropPath && listEquals(other.keyframes, keyframes);

  @override
  int get hashCode => Object.hashAll(keyframes);
}

/// One crop position on the scene strip: keyframe [keyframeIndex] holds
/// (or glides to) its place from [start] to [end], in video time.
@immutable
class CropSpan {
  const CropSpan({
    required this.keyframeIndex,
    required this.start,
    required this.end,
    required this.arrival,
  });

  final int keyframeIndex;
  final Duration start;
  final Duration end;
  final CropArrival arrival;

  Duration get length => end - start;

  bool contains(Duration time) => time >= start && time < end;

  @override
  bool operator ==(Object other) =>
      other is CropSpan &&
      other.keyframeIndex == keyframeIndex &&
      other.start == start &&
      other.end == end &&
      other.arrival == arrival;

  @override
  int get hashCode => Object.hash(keyframeIndex, start, end, arrival);
}

CropAnchor _between(CropKeyframe from, CropKeyframe to, Duration time) {
  if (to.arrival == CropArrival.cut) {
    return from.anchor;
  }
  final span = (to.time - from.time).inMicroseconds;
  final done = (time - from.time).inMicroseconds;
  return from.anchor.towards(to.anchor, done / span);
}

Duration _snapped(Duration time) {
  final tenths = (time.inMicroseconds / _snap.inMicroseconds).round();
  return _snap * tenths;
}

int _byTime(CropKeyframe a, CropKeyframe b) => a.time.compareTo(b.time);
