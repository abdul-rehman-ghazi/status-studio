import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/person_choice.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

const clip = ClipRange(start: Duration.zero, end: Duration(seconds: 10));

const geometry = FollowGeometry(
  clip: clip,
  windowWidth: 0.316,
  windowHeight: 1,
  base: CropAnchor(x: 0.5, y: 0.5),
);

SubjectBox faceAt(double centreX, {double size = 0.1}) =>
    SubjectBox(left: centreX - size / 2, top: 0.35, width: size, height: size);

/// 41 frames, a quarter of a second apart; [facesAt] gives a frame's faces.
SubjectTrack trackOf(List<SubjectBox> Function(int frame) facesAt) {
  return SubjectTrack(
    samples: [
      for (var frame = 0; frame < 41; frame++)
        SubjectSample(
          time: Duration(milliseconds: frame * 250),
          faces: facesAt(frame),
        ),
    ],
    sceneCuts: const [],
  );
}

void main() {
  test('two_people_together_are_both_offered', () {
    final people = choosablePeople(
      trackOf((_) => [faceAt(0.2), faceAt(0.7)]),
      geometry,
    );

    expect(people.length, 2);
  });

  test('one_person_offers_fewer_than_two', () {
    final people = choosablePeople(trackOf((_) => [faceAt(0.2)]), geometry);

    expect(people, isEmpty);
  });

  test('people_who_are_never_together_offer_fewer_than_two', () {
    final people = choosablePeople(
      trackOf((frame) => [faceAt(frame < 20 ? 0.2 : 0.7)]),
      geometry,
    );

    expect(people, isEmpty);
  });

  test('a_face_seen_in_two_frames_is_not_offered', () {
    final people = choosablePeople(
      trackOf(
        (frame) => [faceAt(0.2), if (frame == 5 || frame == 6) faceAt(0.7)],
      ),
      geometry,
    );

    expect(people, isEmpty);
  });

  test('a_face_in_a_tenth_of_its_scene_is_not_offered', () {
    final people = choosablePeople(
      trackOf((frame) => [faceAt(0.2), if (frame < 4) faceAt(0.7)]),
      geometry,
    );

    expect(people, isEmpty);
  });

  test('the_picture_is_the_frame_with_the_most_people', () {
    final people = choosablePeople(
      trackOf(
        (frame) => [
          faceAt(0.2),
          if (frame >= 10 && frame <= 20) faceAt(0.5),
          if (frame >= 15 && frame <= 26) faceAt(0.8),
        ],
      ),
      geometry,
    );

    expect(people.map((person) => person.sampleIndex).toSet(), {15});
  });

  test('ties_go_to_the_frame_with_the_biggest_faces', () {
    final people = choosablePeople(
      trackOf(
        (frame) => [
          faceAt(0.2),
          if (frame < 10) faceAt(0.7),
          if (frame >= 20 && frame < 30) faceAt(0.7, size: 0.2),
        ],
      ),
      geometry,
    );

    expect(people.map((person) => person.sampleIndex).toSet(), {20});
  });

  test('at_most_six_are_offered_the_biggest', () {
    final people = choosablePeople(
      trackOf(
        (_) => [
          for (var i = 0; i < 8; i++)
            faceAt(0.06 + 0.11 * i, size: 0.02 + 0.005 * i),
        ],
      ),
      geometry,
    );

    expect(people.every((person) => person.face.width > 0.027), isTrue);
    expect(people.length, 6);
  });

  test('choices_are_left_to_right', () {
    final people = choosablePeople(
      trackOf((_) => [faceAt(0.8), faceAt(0.2), faceAt(0.5)]),
      geometry,
    );

    expect(people.map((person) => person.face.centreX).toList(), [
      closeTo(0.2, 1e-9),
      closeTo(0.5, 1e-9),
      closeTo(0.8, 1e-9),
    ]);
  });

  test('too_few_faces_find_no_person', () {
    expect(
      () => choosablePeople(trackOf((_) => []), geometry),
      throwsA(isA<NoSubjectFoundException>()),
    );
  });
}
