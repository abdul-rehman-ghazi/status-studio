import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/domain/face_tracks.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

SubjectBox faceAt(double centreX, {double size = 0.1}) =>
    SubjectBox(left: centreX - size / 2, top: 0.35, width: size, height: size);

SubjectSample sampleAt(int frame, List<SubjectBox> faces) => SubjectSample(
  time: Duration(milliseconds: frame * 250),
  faces: faces,
);

void main() {
  test('two_people_in_every_frame_are_two_tracks', () {
    final tracks = trackFaces([
      for (var frame = 0; frame < 4; frame++)
        sampleAt(frame, [faceAt(0.2), faceAt(0.7)]),
    ]);

    expect(tracks.length, 2);
  });

  test('the_typical_face_is_the_average_of_where_the_person_was', () {
    final tracks = trackFaces([
      sampleAt(0, [faceAt(0.3)]),
      sampleAt(1, [faceAt(0.4)]),
    ]);

    expect(tracks.single.typicalFace.centreX, closeTo(0.35, 1e-9));
  });

  test('a_person_unseen_for_a_second_is_the_same_track', () {
    final tracks = trackFaces([
      sampleAt(0, [faceAt(0.3)]),
      sampleAt(5, [faceAt(0.3)]),
    ]);

    expect(tracks.length, 1);
  });

  test('a_person_unseen_for_three_seconds_is_a_new_track', () {
    final tracks = trackFaces([
      sampleAt(0, [faceAt(0.3)]),
      sampleAt(13, [faceAt(0.3)]),
    ]);

    expect(tracks.length, 2);
  });
}
