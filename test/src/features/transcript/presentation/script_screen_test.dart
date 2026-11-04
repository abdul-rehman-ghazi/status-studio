import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/lyrics/application/lyrics_service.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/groq_script_fix_service.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

/// Taller than a phone: the test font is wide, so the tool buttons take a
/// row each and would push the lines out of reach.
Future<void> pumpScript(WidgetTester tester) async {
  await pumpRoutes(tester, [
    AppRoutes.script,
  ], setup: TestSetup(overrides: [draftOverride(scriptDraft)]));
  tester.view.physicalSize = const Size(1080, 3000);
  await tester.pump();
}

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

    await tester.tap(find.text('Real lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('Real lyric line'), findsOneWidget);
  });

  testWidgets('missing_lyrics_keep_the_script_and_say_so', (tester) async {
    await pumpScriptWithLyrics(
      tester,
      FakeLyricsService(failure: const LyricsNotFoundException()),
    );

    await tester.tap(find.text('Real lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('علم بڑی دولت ہے'), findsOneWidget);
    expect(find.textContaining("Couldn't find the lyrics"), findsOneWidget);
  });

  testWidgets('copy_for_ai_puts_the_prompt_and_rows_on_the_clipboard', (
    tester,
  ) async {
    final clipboard = FakeClipboard('')..install();
    await pumpScript(tester);

    await tester.tap(find.text('Copy for AI'));
    await tester.pump();

    expect(
      clipboard.text,
      contains('1 | 00:12.00 | 00:20.60 | صبر کا پھل میٹھا ہوتا ہے'),
    );
  });

  testWidgets('copy_for_ai_sends_only_the_picked_lines', (tester) async {
    final clipboard = FakeClipboard('')..install();
    await pumpRoutes(tester, [
      AppRoutes.script,
    ], setup: TestSetup(overrides: [draftOverride(pickedDraft)]));

    await tester.tap(find.text('Copy for AI'));
    await tester.pump();

    expect(clipboard.text, contains('2 | 00:21.40'));
    expect(clipboard.text, isNot(contains('1 | 00:12.00')));
  });

  testWidgets('paste_fixed_script_replaces_line_text', (tester) async {
    FakeClipboard('1 | 00:12.00 | 00:20.60 | درست متن').install();
    await pumpRoutes(
      tester,
      [AppRoutes.script],
      setup: TestSetup(
        overrides: [
          draftOverride(scriptDraft),
          scriptEditingServiceProvider.overrideWithValue(
            ScriptEditingService(
              store: Future.value(
                TranscriptStore(
                  Directory.systemTemp.createTempSync('paste_fixed'),
                  clock: DateTime.now,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Paste AI reply'));
    await tester.pumpAndSettle();

    expect(find.text('درست متن'), findsOneWidget);
  });

  testWidgets('paste_without_script_rows_keeps_the_script_and_says_so', (
    tester,
  ) async {
    FakeClipboard('Sorry, I cannot help.').install();
    await pumpScript(tester);

    await tester.tap(find.text('Paste AI reply'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't find script lines"), findsOneWidget);
    expect(find.text('علم بڑی دولت ہے'), findsOneWidget);
  });

  Future<void> pumpScriptWithGroq(WidgetTester tester, AskGroq askGroq) =>
      pumpRoutes(
        tester,
        [AppRoutes.script],
        setup: TestSetup(
          overrides: [
            draftOverride(scriptDraft),
            groqScriptFixServiceProvider.overrideWithValue(
              GroqScriptFixService(askGroq: askGroq),
            ),
            scriptEditingServiceProvider.overrideWithValue(
              ScriptEditingService(
                store: Future.value(
                  TranscriptStore(
                    Directory.systemTemp.createTempSync('groq_fix'),
                    clock: DateTime.now,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  testWidgets('fix_with_groq_replaces_line_text', (tester) async {
    await pumpScriptWithGroq(
      tester,
      (_) async => '1 | 00:12.00 | 00:20.60 | درست متن',
    );

    await tester.tap(find.text('Fix with Groq'));
    await tester.pump();
    await tester.pump();

    expect(find.text('درست متن'), findsOneWidget);
  });

  testWidgets('fix_with_groq_without_a_key_offers_settings', (tester) async {
    await pumpScriptWithGroq(
      tester,
      (_) async => throw const NoGroqKeyException(),
    );

    await tester.tap(find.text('Fix with Groq'));
    await tester.pumpAndSettle();

    expect(find.text('Fixing a script needs a free Groq key.'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('fix_with_groq_failing_says_groq_could_not_fix_it', (
    tester,
  ) async {
    await pumpScriptWithGroq(
      tester,
      (_) async => throw const GroqFailedException(500),
    );

    await tester.tap(find.text('Fix with Groq'));
    await tester.pumpAndSettle();

    expect(find.text("Groq couldn't fix this script."), findsOneWidget);
  });

  testWidgets('fix_with_groq_reply_without_rows_keeps_the_script', (
    tester,
  ) async {
    await pumpScriptWithGroq(tester, (_) async => 'I could not find it.');

    await tester.tap(find.text('Fix with Groq'));
    await tester.pumpAndSettle();

    expect(
      find.text("Groq's reply had no script lines. Try again."),
      findsOneWidget,
    );
    expect(find.text('علم بڑی دولت ہے'), findsOneWidget);
  });

  testWidgets('fix_with_groq_turns_the_other_fix_buttons_off_while_it_runs', (
    tester,
  ) async {
    await pumpScriptWithGroq(tester, (_) => Completer<String>().future);

    await tester.tap(find.text('Fix with Groq'));
    await tester.pump();

    final paste = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Paste AI reply'),
    );
    expect(paste.onPressed, isNull);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('cancel_ignores_the_reply_and_keeps_the_script', (tester) async {
    final reply = Completer<String>();
    await pumpScriptWithGroq(tester, (_) => reply.future);
    await tester.tap(find.text('Fix with Groq'));
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    reply.complete('1 | 00:12.00 | 00:20.60 | درست متن');
    await tester.pumpAndSettle();

    expect(find.text('درست متن'), findsNothing);
    expect(find.text('Fix with Groq'), findsOneWidget);
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

/// Stands in for the system clipboard; returns what was last copied.
class FakeClipboard {
  FakeClipboard(this.text);

  String text;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            text = (call.arguments as Map)['text'] as String;
          }
          return call.method == 'Clipboard.getData' ? {'text': text} : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }
}

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
