import 'package:status_studio/src/features/style/domain/face_tracks.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/features/style/domain/subject_path.dart';

const _mostPeopleOffered = 6;

/// One face or body to choose in a scene's picture, and the person it is
/// followed as (spec FR-27).
class ScenePerson {
  const ScenePerson({required this.box, required this.track});

  final SubjectBox box;
  final FaceTrack track;
}

/// The frame a scene is asked about, and who can be chosen in it.
class ScenePicture {
  const ScenePicture({
    required this.sampleIndex,
    required this.faces,
    this.bodies = const [],
  });

  /// The frame's place in the whole track's samples.
  final int sampleIndex;

  /// Left to right.
  final List<ScenePerson> faces;

  /// Left to right. Empty until there is a body detector (M25 task 5).
  final List<ScenePerson> bodies;
}

/// The scene's fullest frame (spec FR-27): the one with the most people, else
/// the biggest faces, else the earliest. It offers those people only who are
/// seen often enough in the scene to be someone, not a false face, and at most
/// the biggest six.
ScenePicture pictureOfScene(SubjectScene scene) {
  final lasting = lastingPeople(
    trackFaces(scene.samples),
    scene.samples.length,
  );
  final joined = [
    for (final person in lasting) withTheirOtherSightings(person, lasting),
  ];
  final frames = [
    for (var i = 0; i < scene.samples.length; i++)
      [
        for (final (index, person) in lasting.indexed)
          if (person.faceAt(i) case final face?)
            ScenePerson(box: face, track: joined[index]),
      ],
  ];
  var fullestIndex = 0;
  for (var i = 1; i < frames.length; i++) {
    if (_isFuller(frames[i], than: frames[fullestIndex])) {
      fullestIndex = i;
    }
  }
  return ScenePicture(
    sampleIndex: scene.firstIndex + fullestIndex,
    faces: _biggestLeftToRight(frames[fullestIndex]),
  );
}

/// More people, else bigger faces; on a tie the earlier stays.
bool _isFuller(List<ScenePerson> frame, {required List<ScenePerson> than}) {
  if (frame.length != than.length) {
    return frame.length > than.length;
  }
  return _areaOf(frame) > _areaOf(than);
}

double _areaOf(List<ScenePerson> frame) =>
    frame.fold(0.0, (sum, person) => sum + person.box.area);

List<ScenePerson> _biggestLeftToRight(List<ScenePerson> frame) {
  final biggest = [...frame]..sort((a, b) => b.box.area.compareTo(a.box.area));
  return biggest.take(_mostPeopleOffered).toList()
    ..sort((a, b) => a.box.centreX.compareTo(b.box.centreX));
}
