import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/features/style/domain/subject_path.dart';

const framesPerSecond = 4;

/// A 9:16 window in a 16:9 frame: 31.6 % of the width, all of the height.
FollowGeometry geometryFor(
  ClipRange clip, {
  double windowHeight = 1,
  CropAnchor base = const CropAnchor(x: 0.5, y: 0.5),
}) => FollowGeometry(
  clip: clip,
  windowWidth: 0.316,
  windowHeight: windowHeight,
  base: base,
);

ClipRange clipOfSeconds(double start, double end) => ClipRange(
  start: Duration(milliseconds: (start * 1000).round()),
  end: Duration(milliseconds: (end * 1000).round()),
);

SubjectBox faceAt(double centreX, {double size = 0.1, double centreY = 0.4}) =>
    SubjectBox(
      left: centreX - size / 2,
      top: centreY - size / 2,
      width: size,
      height: size,
    );

/// One sample per frame, from the clip start; [facesAt] gives a frame's
/// faces from its index.
SubjectTrack trackOf(
  ClipRange clip,
  List<SubjectBox> Function(int frame) facesAt, {
  List<Duration>? sceneCuts,
}) {
  final frames =
      (clip.length.inMilliseconds / 1000 * framesPerSecond).floor() + 1;
  return SubjectTrack(
    samples: [
      for (var frame = 0; frame < frames; frame++)
        SubjectSample(
          time: clip.start + Duration(milliseconds: frame * 250),
          faces: facesAt(frame),
        ),
    ],
    sceneCuts: sceneCuts,
  );
}

void main() {
  final tenSeconds = clipOfSeconds(20, 30);

  group('followSubject', () {
    test('a_steady_face_gives_one_keyframe', () {
      final path = followSubject(
        trackOf(tenSeconds, (_) => [faceAt(0.5)]),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.length, 1);
    });

    test('the_first_keyframe_is_at_the_clip_start', () {
      final path = followSubject(
        trackOf(tenSeconds, (_) => [faceAt(0.5)]),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.first.time, tenSeconds.start);
    });

    test('a_face_that_drifts_across_the_frame_gives_a_few_glides', () {
      final path = followSubject(
        trackOf(tenSeconds, (frame) => [faceAt(0.2 + 0.7 * frame / 40)]),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.length, lessThanOrEqualTo(4));
      expect(
        path.keyframes.every(
          (keyframe) => keyframe.arrival == CropArrival.glide,
        ),
        isTrue,
      );
    });

    test('a_drifting_face_ends_with_the_window_near_the_right', () {
      final path = followSubject(
        trackOf(tenSeconds, (frame) => [faceAt(0.2 + 0.7 * frame / 40)]),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.last.anchor.x, greaterThan(0.85));
    });

    test('jitter_of_a_few_hundredths_gives_one_keyframe', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [faceAt(0.5 + (frame.isEven ? 0.01 : -0.01))],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.length, 1);
    });

    test('two_faces_follow_the_larger', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (_) => [faceAt(0.7, size: 0.05), faceAt(0.3, size: 0.2)],
        ),
        geometryFor(tenSeconds),
      );

      // Window centred on 0.3: (0.3 − 0.158) / 0.684.
      expect(path.keyframes.single.anchor.x, closeTo(0.2076, 0.001));
    });

    test('a_larger_face_beside_the_followed_one_does_not_take_over', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => frame < 8
              ? [faceAt(0.3)]
              : [faceAt(0.3), faceAt(0.75, size: 0.3)],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.single.anchor.x, closeTo(0.2076, 0.001));
    });

    test('a_scene_cut_gives_a_cut_at_its_time', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [faceAt(frame < 20 ? 0.25 : 0.75)],
          sceneCuts: [const Duration(seconds: 25)],
        ),
        geometryFor(tenSeconds),
      );

      final cut = path.keyframes.firstWhere(
        (keyframe) => keyframe.arrival == CropArrival.cut,
      );
      expect(cut.time, const Duration(seconds: 25));
    });

    test('after_a_cut_the_window_is_on_the_new_scenes_face', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [faceAt(frame < 20 ? 0.25 : 0.75)],
          sceneCuts: [const Duration(seconds: 25)],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.last.anchor.x, closeTo(0.8667, 0.01));
    });

    test('a_big_jump_with_no_cut_data_is_a_cut', () {
      final path = followSubject(
        trackOf(tenSeconds, (frame) => [faceAt(frame < 20 ? 0.25 : 0.75)]),
        geometryFor(tenSeconds),
      );

      expect(
        path.keyframes.where((keyframe) => keyframe.arrival == CropArrival.cut),
        hasLength(1),
      );
    });

    test('a_big_jump_the_scene_detector_missed_is_still_a_cut', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [faceAt(frame < 20 ? 0.25 : 0.75)],
          sceneCuts: const [],
        ),
        geometryFor(tenSeconds),
      );

      expect(
        path.keyframes.where((keyframe) => keyframe.arrival == CropArrival.cut),
        hasLength(1),
      );
    });

    test('a_jump_beside_a_known_cut_is_not_a_second_cut', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [faceAt(frame < 20 ? 0.25 : 0.75)],
          sceneCuts: [const Duration(milliseconds: 25100)],
        ),
        geometryFor(tenSeconds),
      );

      expect(
        path.keyframes.where((keyframe) => keyframe.arrival == CropArrival.cut),
        hasLength(1),
      );
    });

    test('a_cut_just_after_the_clip_start_moves_the_first_keyframe', () {
      final clip = clipOfSeconds(10, 40);

      final path = followSubject(
        trackOf(
          clip,
          (frame) => [faceAt(frame < 2 ? 0.25 : 0.75)],
          sceneCuts: [const Duration(milliseconds: 10300)],
        ),
        geometryFor(clip),
      );

      // The second shot's face is at 0.75: (0.75 − 0.158) / 0.684.
      expect(path.keyframes.first.anchor.x, closeTo(0.8655, 0.01));
    });

    test('a_second_without_a_face_holds_the_last_anchor', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => frame >= 16 && frame < 20 ? [] : [faceAt(0.3)],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.length, 1);
    });

    test('with_room_on_x_only_y_keeps_the_base_anchor', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [
            faceAt(0.2 + 0.7 * frame / 40, centreY: 0.2 + frame / 80),
          ],
        ),
        geometryFor(tenSeconds, base: const CropAnchor(x: 0.5, y: 0.3)),
      );

      expect(
        path.keyframes.every((keyframe) => keyframe.anchor.y == 0.3),
        isTrue,
      );
    });

    test('with_room_on_y_the_face_sits_a_third_of_the_way_down_the_window', () {
      final path = followSubject(
        trackOf(tenSeconds, (_) => [faceAt(0.5, centreY: 0.5)]),
        geometryFor(tenSeconds, windowHeight: 0.5),
      );

      // Window top = 0.5 − 0.5 / 3 = 0.3333; room = 0.5.
      expect(path.keyframes.single.anchor.y, closeTo(0.6667, 0.001));
    });

    test(
      'a_start_between_tenths_gets_its_first_keyframe_at_the_next_tenth',
      () {
        final oddClip = clipOfSeconds(12.34, 22.34);

        final path = followSubject(
          trackOf(oddClip, (_) => [faceAt(0.5)]),
          geometryFor(oddClip),
        );

        expect(path.keyframes.first.time, const Duration(milliseconds: 12400));
      },
    );
  });

  group('followSubject with several people', () {
    final threeSeconds = clipOfSeconds(0, 3);

    int cutsIn(CropPath path) =>
        path.keyframes.where((k) => k.arrival == CropArrival.cut).length;

    test('a_person_who_moves_fast_is_still_the_one_followed', () {
      // Moves 0.07 a frame, so the boxes of two frames no longer overlap
      // enough to match by overlap; a bigger, briefly seen face passes by.
      final path = followSubject(
        trackOf(
          threeSeconds,
          (frame) => [
            faceAt(0.1 + 0.07 * frame),
            if (frame >= 4 && frame <= 8) faceAt(0.9, size: 0.14),
          ],
        ),
        geometryFor(threeSeconds),
      );

      expect(cutsIn(path), 0);
    });

    test('a_larger_face_seen_only_at_the_start_is_not_followed', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [faceAt(0.3), if (frame < 2) faceAt(0.8, size: 0.3)],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.single.anchor.x, closeTo(0.2076, 0.001));
    });

    test('someone_else_while_the_person_is_missed_is_not_followed', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => frame >= 10 && frame <= 13
              ? [faceAt(0.75, size: 0.2)]
              : [faceAt(0.3)],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.single.anchor.x, closeTo(0.2076, 0.001));
    });

    test('a_small_face_always_in_the_background_is_not_the_subject', () {
      final path = followSubject(
        trackOf(
          tenSeconds,
          (frame) => [
            faceAt(0.8, size: 0.04),
            if (frame < 38) faceAt(0.3, size: 0.12),
          ],
        ),
        geometryFor(tenSeconds),
      );

      expect(path.keyframes.first.anchor.x, closeTo(0.2076, 0.001));
    });
  });

  group('followPerson', () {
    // A big person on the left and a small one on the right; the automatic
    // pick is the big one.
    final bigOne = faceAt(0.3, size: 0.2);
    final smallOne = faceAt(0.75, size: 0.08);
    // Window centred on 0.75: (0.75 − 0.158) / 0.684.
    const smallOnesAnchor = 0.8655;
    const bigOnesAnchor = 0.2076;

    SubjectTrack together({
      List<Duration>? sceneCuts,
      List<SubjectBox> Function(int frame)? facesAt,
    }) => trackOf(
      tenSeconds,
      facesAt ?? (_) => [bigOne, smallOne],
      sceneCuts: sceneCuts,
    );

    PersonChoice smallOneAt(SubjectTrack track, int sampleIndex) =>
        PersonChoice(
          sampleIndex: sampleIndex,
          face: track.samples[sampleIndex].faces.firstWhere(
            (face) => face.width < 0.1,
          ),
        );

    test('the_chosen_smaller_face_is_followed', () {
      final track = together();

      final path = followPerson(
        track,
        geometryFor(tenSeconds),
        smallOneAt(track, 0),
      );

      expect(path.keyframes.single.anchor.x, closeTo(smallOnesAnchor, 0.001));
    });

    test('the_chosen_person_missed_for_a_second_holds_the_crop', () {
      final track = together(
        facesAt: (frame) =>
            frame >= 10 && frame <= 13 ? [bigOne] : [bigOne, smallOne],
      );

      final path = followPerson(
        track,
        geometryFor(tenSeconds),
        smallOneAt(track, 0),
      );

      expect(path.keyframes.single.anchor.x, closeTo(smallOnesAnchor, 0.001));
    });

    test('a_later_scene_follows_the_face_in_the_same_place', () {
      final track = together(sceneCuts: [const Duration(seconds: 25)]);

      final path = followPerson(
        track,
        geometryFor(tenSeconds),
        smallOneAt(track, 0),
      );

      expect(path.keyframes.last.anchor.x, closeTo(smallOnesAnchor, 0.001));
    });

    test('an_earlier_scene_follows_the_face_in_the_same_place', () {
      final track = together(sceneCuts: [const Duration(seconds: 25)]);

      final path = followPerson(
        track,
        geometryFor(tenSeconds),
        smallOneAt(track, 30),
      );

      expect(path.keyframes.first.anchor.x, closeTo(smallOnesAnchor, 0.001));
    });

    test('a_scene_without_such_a_face_uses_the_automatic_pick', () {
      final track = together(
        sceneCuts: [const Duration(seconds: 25)],
        facesAt: (frame) => frame < 20 ? [bigOne, smallOne] : [bigOne],
      );

      final path = followPerson(
        track,
        geometryFor(tenSeconds),
        smallOneAt(track, 0),
      );

      expect(path.keyframes.last.anchor.x, closeTo(bigOnesAnchor, 0.001));
    });

    test('choosing_keeps_the_same_cuts', () {
      final track = together(sceneCuts: [const Duration(seconds: 25)]);
      List<Duration> cutsOf(CropPath path) => [
        for (final keyframe in path.keyframes)
          if (keyframe.arrival == CropArrival.cut) keyframe.time,
      ];

      final chosen = followPerson(
        track,
        geometryFor(tenSeconds),
        smallOneAt(track, 0),
      );

      expect(
        cutsOf(chosen),
        cutsOf(followSubject(track, geometryFor(tenSeconds))),
      );
    });

    test('a_choice_matching_no_face_is_an_argument_error', () {
      final track = together();

      expect(
        () => followPerson(
          track,
          geometryFor(tenSeconds),
          PersonChoice(sampleIndex: 0, face: faceAt(0.5, size: 0.05)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('followSubject with a busy clip', () {
    final ninetySeconds = clipOfSeconds(0, 90);
    final random = math.Random(7);
    final wandering = trackOf(
      ninetySeconds,
      (frame) => [
        faceAt(0.5 + 0.4 * math.sin(frame / 7) + 0.1 * random.nextDouble()),
      ],
      sceneCuts: [
        for (var second = 10; second < 90; second += 10)
          Duration(seconds: second),
      ],
    );

    test('has_at_most_twelve_keyframes', () {
      final path = followSubject(wandering, geometryFor(ninetySeconds));

      expect(path.keyframes.length, lessThanOrEqualTo(12));
    });

    test('keeps_keyframes_half_a_second_apart', () {
      final path = followSubject(wandering, geometryFor(ninetySeconds));

      final gaps = [
        for (var i = 1; i < path.keyframes.length; i++)
          path.keyframes[i].time - path.keyframes[i - 1].time,
      ];
      expect(
        gaps.every((gap) => gap >= const Duration(milliseconds: 500)),
        isTrue,
      );
    });

    test('keeps_every_keyframe_inside_the_clip', () {
      final path = followSubject(wandering, geometryFor(ninetySeconds));

      expect(
        path.keyframes.every(
          (keyframe) =>
              keyframe.time >= ninetySeconds.start &&
              keyframe.time <= ninetySeconds.end,
        ),
        isTrue,
      );
    });
  });

  group('followSubject with quick cuts', () {
    final minute = clipOfSeconds(0, 60);
    final quickCuts = trackOf(
      minute,
      (frame) => [faceAt((frame ~/ 12).isEven ? 0.2 : 0.8)],
      sceneCuts: [
        for (var second = 3; second < 60; second += 3)
          Duration(seconds: second),
      ],
    );

    test('stays_within_twelve_keyframes', () {
      final path = followSubject(quickCuts, geometryFor(minute));

      expect(path.keyframes.length, lessThanOrEqualTo(12));
    });

    test('still_follows_to_the_end_of_the_clip', () {
      final path = followSubject(quickCuts, geometryFor(minute));

      expect(
        path.keyframes.last.time,
        greaterThanOrEqualTo(const Duration(seconds: 40)),
      );
    });
  });

  group('no person', () {
    test('faces_in_a_tenth_of_the_frames_find_no_person', () {
      expect(
        () => followSubject(
          trackOf(
            tenSecondsClip(),
            (frame) => frame % 10 == 0 ? [faceAt(0.5)] : [],
          ),
          geometryFor(tenSecondsClip()),
        ),
        throwsA(isA<NoSubjectFoundException>()),
      );
    });

    test('two_faces_in_a_long_clip_find_no_person', () {
      expect(
        () => followSubject(
          trackOf(tenSecondsClip(), (frame) => frame < 2 ? [faceAt(0.5)] : []),
          geometryFor(tenSecondsClip()),
        ),
        throwsA(isA<NoSubjectFoundException>()),
      );
    });

    test('a_clip_with_no_faces_finds_no_person', () {
      expect(
        () => followSubject(
          trackOf(tenSecondsClip(), (_) => []),
          geometryFor(tenSecondsClip()),
        ),
        throwsA(isA<NoSubjectFoundException>()),
      );
    });
  });
}

ClipRange tenSecondsClip() => clipOfSeconds(20, 30);
