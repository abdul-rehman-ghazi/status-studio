import 'package:status_studio/src/features/style/domain/face_tracks.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/features/style/domain/subject_path.dart';

const _leastSightings = 3;
const _leastShareOfScene = 0.2;
const _mostPeopleOffered = 6;
const _fewestToAsk = 2;

/// The people to choose between, all in one frame, left to right; fewer than
/// two means there is nothing to ask.
///
/// Throws [NoSubjectFoundException] when faces are too rare to follow anyone,
/// as [followSubject] does.
List<PersonChoice> choosablePeople(
  SubjectTrack track,
  FollowGeometry geometry,
) {
  requireEnoughFaces(track.samples);
  final frames = [
    for (final scene in scenesOf(track, geometry)) ..._framesOf(scene),
  ];
  if (frames.isEmpty) {
    return const [];
  }
  final fullest = frames.reduce(_fuller);
  if (fullest.length < _fewestToAsk) {
    return const [];
  }
  final biggest = [...fullest]
    ..sort((a, b) => b.face.area.compareTo(a.face.area));
  return biggest.take(_mostPeopleOffered).toList()
    ..sort((a, b) => a.face.centreX.compareTo(b.face.centreX));
}

/// The people of a scene in each of its frames.
List<List<PersonChoice>> _framesOf(SubjectScene scene) {
  final people = _peopleOf(scene);
  return [
    for (var i = 0; i < scene.samples.length; i++)
      [
        for (final person in people)
          if (person.faceAt(i) case final face?)
            PersonChoice(sampleIndex: scene.firstIndex + i, face: face),
      ],
  ];
}

/// The tracks seen often enough to be someone, not a false face.
List<FaceTrack> _peopleOf(SubjectScene scene) {
  return trackFaces(scene.samples)
      .where(
        (track) =>
            track.sightings >= _leastSightings &&
            track.sightings >= scene.samples.length * _leastShareOfScene,
      )
      .toList();
}

/// The frame with more people, else the one with the bigger faces; on a tie
/// the earlier stays.
List<PersonChoice> _fuller(List<PersonChoice> best, List<PersonChoice> next) {
  if (next.length != best.length) {
    return next.length > best.length ? next : best;
  }
  return _areaOf(next) > _areaOf(best) ? next : best;
}

double _areaOf(List<PersonChoice> frame) =>
    frame.fold(0.0, (sum, person) => sum + person.face.area);
