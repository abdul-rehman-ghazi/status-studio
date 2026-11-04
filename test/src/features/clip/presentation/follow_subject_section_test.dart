import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/presentation/follow_subject_section.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';

Future<void> pumpSection(WidgetTester tester, FollowState state) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FollowSubjectSection(
          state: state,
          canStart: true,
          onStart: () {},
          onCancel: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('before_any_frames_are_ready_the_bar_is_indeterminate', (
    tester,
  ) async {
    await pumpSection(tester, const FollowRunning(0));

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );

    expect(bar.value, isNull);
  });

  testWidgets('before_any_frames_are_ready_no_percent_is_shown', (
    tester,
  ) async {
    await pumpSection(tester, const FollowRunning(0));

    expect(find.text('Finding the person…'), findsOneWidget);
  });

  testWidgets('once_frames_are_being_looked_at_the_percent_shows', (
    tester,
  ) async {
    await pumpSection(tester, const FollowRunning(0.45));

    expect(find.text('Finding the person… 45 %'), findsOneWidget);
  });

  testWidgets('once_frames_are_being_looked_at_the_bar_has_a_value', (
    tester,
  ) async {
    await pumpSection(tester, const FollowRunning(0.45));

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );

    expect(bar.value, 0.45);
  });

  testWidgets('the_button_is_off_until_the_clip_has_downloaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowSubjectSection(
            state: const FollowIdle(),
            canStart: false,
            onStart: () {},
            onCancel: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));

    expect(button.onPressed, isNull);
  });
}
