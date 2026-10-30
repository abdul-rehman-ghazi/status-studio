import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

Future<void> pumpScript(WidgetTester tester) => pumpRoutes(tester, [
  AppRoutes.script,
], setup: TestSetup(overrides: [draftOverride(scriptDraft)]));

Future<void> pickLinesOneToThree(WidgetTester tester) async {
  await tester.tap(find.text('علم بڑی دولت ہے'));
  await tester.tap(find.text('وقت کی قدر کرو'));
  await tester.pump();
}

void main() {
  testWidgets('next_disabled_until_start_and_end_picked', (tester) async {
    await pumpScript(tester);

    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Pick a start and an end'),
    );

    expect(next.onPressed, isNull);
  });

  testWidgets('two_taps_enable_next', (tester) async {
    await pumpScript(tester);

    await pickLinesOneToThree(tester);

    expect(
      find.widgetWithText(FilledButton, 'Next: fine-tune'),
      findsOneWidget,
    );
  });

  testWidgets('first_tap_asks_for_the_end_line', (tester) async {
    await pumpScript(tester);

    await tester.tap(find.text('علم بڑی دولت ہے'));
    await tester.pump();

    expect(find.text('Now tap the line where it ends'), findsOneWidget);
  });

  testWidgets('range_hint_shows_clip_times_and_length', (tester) async {
    await pumpScript(tester);

    await pickLinesOneToThree(tester);

    expect(
      find.text('Clip 0:21 – 0:48 · 27.4 s. Tap a line to start over.'),
      findsOneWidget,
    );
  });

  testWidgets('automatic_language_shows_detected_language', (tester) async {
    await pumpScript(tester);

    expect(find.text('Urdu (detected)'), findsOneWidget);
  });

  testWidgets('next_opens_fine_tune', (tester) async {
    await pumpScript(tester);
    await pickLinesOneToThree(tester);

    await tester.tap(find.text('Next: fine-tune'));
    await tester.pumpAndSettle();

    expect(find.text('Lines in this clip'), findsOneWidget);
  });
}
