import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/lyrics/application/lyrics_service.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
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

  testWidgets('saved_script_shows_banner', (tester) async {
    await pumpRoutes(
      tester,
      [AppRoutes.script],
      setup: TestSetup(
        overrides: [
          draftOverride(scriptDraft),
          scriptProgressProvider.overrideWith(SavedRunController.new),
        ],
      ),
    );

    expect(find.text('Using the saved script from 7 Oct'), findsOneWidget);
  });

  testWidgets('language_change_clears_selection', (tester) async {
    await pumpRoutes(tester, [
      AppRoutes.script,
    ], setup: TestSetup(overrides: [draftOverride(pickedDraft)]));

    await tester.tap(find.byType(DropdownButtonFormField<ScriptLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('Tap the line where your clip starts'), findsOneWidget);
  });

  testWidgets('real_lyrics_replace_the_script_lines', (tester) async {
    await pumpScriptWithLyrics(
      tester,
      FakeLyricsService(
        lines: const [
          TranscriptLine(
            index: 0,
            text: 'Real lyric line',
            start: Duration(seconds: 5),
            end: Duration(seconds: 9),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Get the real lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('Real lyric line'), findsOneWidget);
  });

  testWidgets('missing_lyrics_keep_the_script_and_say_so', (tester) async {
    await pumpScriptWithLyrics(
      tester,
      FakeLyricsService(failure: const LyricsNotFoundException()),
    );

    await tester.tap(find.text('Get the real lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('علم بڑی دولت ہے'), findsOneWidget);
    expect(find.textContaining("Couldn't find the lyrics"), findsOneWidget);
  });

  testWidgets('failed_run_shows_message_and_retry', (tester) async {
    await pumpRoutes(
      tester,
      [AppRoutes.script],
      setup: TestSetup(
        overrides: [
          draftOverride(scriptDraft),
          scriptProgressProvider.overrideWith(FailedRunController.new),
        ],
      ),
    );

    expect(
      find.textContaining("You're offline", findRichText: true),
      findsOneWidget,
    );
  });
}

/// Answers with [lines], or fails with [failure]; never touches the network.
class FakeLyricsService implements LyricsService {
  FakeLyricsService({this.lines, this.failure});

  final List<TranscriptLine>? lines;
  final Exception? failure;

  @override
  Future<Transcript> replaceScript(
    SourceVideo video,
    ScriptLanguage language,
  ) async {
    if (failure case final error?) {
      throw error;
    }
    return Transcript(languageCode: 'en', lines: lines!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pumpScriptWithLyrics(
  WidgetTester tester,
  FakeLyricsService lyrics,
) => pumpRoutes(
  tester,
  [AppRoutes.script],
  setup: TestSetup(
    overrides: [
      draftOverride(scriptDraft),
      lyricsServiceProvider.overrideWithValue(lyrics),
    ],
  ),
);

/// A finished run that came from the saved scripts.
class SavedRunController extends ScriptProgressController {
  @override
  AsyncValue<ScriptProgress> build() => AsyncData(
    ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: fixture,
      savedAt: DateTime(2026, 10, 7),
    ),
  );
}

/// A run that stopped partway: the lines so far stay on screen.
class FailedRunController extends ScriptProgressController {
  @override
  AsyncValue<ScriptProgress> build() =>
      const AsyncError(OfflineException('lost'), StackTrace.empty);
}
