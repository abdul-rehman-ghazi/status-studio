import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/presentation/person_chooser_sheet.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

import '../../../../helpers/fake_follow.dart';

const _picture = Key('person-picture');

FollowChoosing choosingBetween(List<SubjectBox> faces) => FollowChoosing(
  picture: File('/no/such/frame.jpg'),
  pictureSize: const OutputSize(1920, 1080),
  choices: [for (final face in faces) PersonChoice(sampleIndex: 3, face: face)],
);

class Taps {
  final chosen = <PersonChoice>[];
  var chosenForMe = 0;
  var cancelled = 0;
}

Future<Taps> pumpSheet(WidgetTester tester, FollowChoosing choosing) async {
  final taps = Taps();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PersonChooserSheet(
          choosing: choosing,
          onChosen: taps.chosen.add,
          onChooseForMe: () => taps.chosenForMe++,
          onCancel: () => taps.cancelled++,
        ),
      ),
    ),
  );
  return taps;
}

/// A point in the picture, as fractions of its width and height, plus an
/// offset in dp.
Offset pointInPicture(
  WidgetTester tester,
  double x,
  double y, {
  Offset plus = Offset.zero,
}) {
  final rect = tester.getRect(find.byKey(_picture));
  return rect.topLeft + Offset(rect.width * x, rect.height * y) + plus;
}

void main() {
  final twoPeople = choosingBetween([leftFace, rightFace]);

  testWidgets('every_choice_has_a_person_label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester, twoPeople);

    expect(find.bySemanticsLabel('Person 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Person 2'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('people_are_numbered_left_to_right', (tester) async {
    await pumpSheet(tester, twoPeople);

    final one = tester.getCenter(find.text('1'));
    final two = tester.getCenter(find.text('2'));

    expect(one.dx, lessThan(two.dx));
  });

  testWidgets('tapping_inside_a_face_chooses_it', (tester) async {
    final taps = await pumpSheet(tester, twoPeople);

    await tester.tapAt(pointInPicture(tester, 0.75, 0.4));

    expect(taps.chosen, [twoPeople.choices.last]);
  });

  testWidgets('a_tap_just_outside_a_small_face_chooses_it', (tester) async {
    final taps = await pumpSheet(tester, twoPeople);

    // 20 dp right of the right face's edge, which is at 0.8 of the width.
    await tester.tapAt(
      pointInPicture(tester, 0.8, 0.4, plus: const Offset(20, 0)),
    );

    expect(taps.chosen, [twoPeople.choices.last]);
  });

  testWidgets('a_far_tap_chooses_nothing', (tester) async {
    final taps = await pumpSheet(tester, twoPeople);

    await tester.tapAt(pointInPicture(tester, 0.5, 0.9));

    expect(taps.chosen, isEmpty);
  });

  testWidgets('a_tap_between_two_close_faces_chooses_the_nearer', (
    tester,
  ) async {
    final close = choosingBetween(const [
      SubjectBox(left: 0.1, top: 0.35, width: 0.1, height: 0.1),
      SubjectBox(left: 0.2625, top: 0.35, width: 0.1, height: 0.1),
    ]);
    final taps = await pumpSheet(tester, close);

    // 18 dp from the first face's edge and 22 dp from the second's.
    await tester.tapAt(
      pointInPicture(tester, 0.2, 0.4, plus: const Offset(18, 0)),
    );

    expect(taps.chosen, [close.choices.first]);
  });

  testWidgets('choose_for_me_calls_back', (tester) async {
    final taps = await pumpSheet(tester, twoPeople);

    await tester.tap(find.text('Choose for me'));

    expect(taps.chosenForMe, 1);
  });

  testWidgets('cancel_calls_back', (tester) async {
    final taps = await pumpSheet(tester, twoPeople);

    await tester.tap(find.text('Cancel'));

    expect(taps.cancelled, 1);
  });

  testWidgets('the_picture_keeps_the_clips_aspect', (tester) async {
    await pumpSheet(tester, twoPeople);

    final size = tester.getSize(find.byKey(_picture));

    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('the_picture_is_at_most_360_dp_high', (tester) async {
    await pumpSheet(tester, twoPeople);

    expect(tester.getSize(find.byKey(_picture)).height, lessThanOrEqualTo(360));
  });

  testWidgets('the_title_and_hint_show', (tester) async {
    await pumpSheet(tester, twoPeople);

    expect(find.text('Who should the crop follow?'), findsOneWidget);
    expect(find.text('Tap a face.'), findsOneWidget);
  });
}
