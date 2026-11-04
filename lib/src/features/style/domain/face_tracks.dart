import 'dart:math' as math;

import 'package:status_studio/src/features/style/domain/subject_box.dart';

const _leastShareOfLongest = 0.9;

/// How long a person can be unseen (a missed detection, a turned head) and
/// still be picked up again as the same person.
const longestFaceGap = Duration(seconds: 2);

/// One person's faces through a stretch of samples, by sample index (spec
/// FR-23).
class FaceTrack {
  FaceTrack._(int sampleIndex, this._lastTime, SubjectBox face)
    : _last = face,
      _areaSeen = face.area,
      _faces = {sampleIndex: face};

  final Map<int, SubjectBox> _faces;
  SubjectBox _last;
  Duration _lastTime;
  double _areaSeen;

  int get sightings => _faces.length;

  /// The sum of the face's areas, to tell apart people seen about as long.
  double get areaSeen => _areaSeen;

  /// The face at [sampleIndex]; null when the person is not seen there.
  SubjectBox? faceAt(int sampleIndex) => _faces[sampleIndex];

  /// The average of the person's faces: where they usually are, and how big.
  SubjectBox get typicalFace {
    final faces = _faces.values;
    double mean(double Function(SubjectBox face) of) =>
        faces.map(of).reduce((a, b) => a + b) / faces.length;
    return SubjectBox(
      left: mean((face) => face.left),
      top: mean((face) => face.top),
      width: mean((face) => face.width),
      height: mean((face) => face.height),
    );
  }

  bool _canTake(SubjectBox face, Duration time) =>
      time - _lastTime <= longestFaceGap && _last.couldBeSameFaceAs(face);

  double _distanceTo(SubjectBox face) => math.max(
    (face.centreX - _last.centreX).abs(),
    (face.centreY - _last.centreY).abs(),
  );

  void _add(int sampleIndex, Duration time, SubjectBox face) {
    _faces[sampleIndex] = face;
    _last = face;
    _lastTime = time;
    _areaSeen += face.area;
  }
}

/// Joins each frame's faces to the people seen before, so a person is one
/// track however the others come and go. Indices are positions in [samples].
List<FaceTrack> trackFaces(List<SubjectSample> samples) {
  final tracks = <FaceTrack>[];
  for (final (index, sample) in samples.indexed) {
    final taken = <FaceTrack>{};
    final largestFirst = [...sample.faces]
      ..sort((a, b) => b.area.compareTo(a.area));
    for (final face in largestFirst) {
      final open = tracks.where(
        (track) => !taken.contains(track) && track._canTake(face, sample.time),
      );
      if (open.isEmpty) {
        final started = FaceTrack._(index, sample.time, face);
        tracks.add(started);
        taken.add(started);
        continue;
      }
      final nearest = open.reduce(
        (best, next) =>
            next._distanceTo(face) < best._distanceTo(face) ? next : best,
      );
      nearest._add(index, sample.time, face);
      taken.add(nearest);
    }
  }
  return tracks;
}

/// The person to follow: among those on screen for most of the scene, the
/// biggest. A bigger face that only passes through is not the subject, and
/// neither is a small one in the background that is always there. Null when
/// there are no people.
FaceTrack? mostProminent(List<FaceTrack> tracks) {
  if (tracks.isEmpty) {
    return null;
  }
  final longest = tracks.map((track) => track.sightings).reduce(math.max);
  final lastingMost = tracks.where(
    (track) => track.sightings >= longest * _leastShareOfLongest,
  );
  return lastingMost.reduce(
    (best, next) => next.areaSeen > best.areaSeen ? next : best,
  );
}
