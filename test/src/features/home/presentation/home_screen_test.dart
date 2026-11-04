import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';

import '../../../../helpers/fine_tune_drafts.dart';
import '../../../../helpers/pump_app.dart';
import '../../../../helpers/recent_reels.dart';
import '../../../../helpers/saved_scripts.dart';

void main() {
  testWidgets('home_shows_new_reel_button', (tester) async {
    await pumpApp(tester);

    expect(find.text('New reel'), findsOneWidget);
  });

  testWidgets('new_reel_opens_source_screen', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('New reel'));
    await tester.pumpAndSettle();

    expect(find.text('YouTube link'), findsOneWidget);
  });

  testWidgets('home_shows_empty_recent_section', (tester) async {
    await pumpApp(tester);

    expect(
      find.text('Your reels and scripts will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('settings_button_opens_settings', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  group('recent reels', () {
    late Directory folder;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('home_screen_test');
    });

    tearDown(() => folder.delete(recursive: true));

    List<RecentReel> twoReels() => [
      recentReel(folder, title: 'Newest reel', minutesOld: 1),
      recentReel(folder, title: 'Older reel', minutesOld: 60),
    ];

    testWidgets('home_lists_recent_reels_newest_first', (tester) async {
      await pumpApp(tester, setup: TestSetup(recentReels: twoReels()));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Newest reel')).dy,
        lessThan(tester.getTopLeft(find.text('Older reel')).dy),
      );
    });

    testWidgets('tapping_recent_reel_opens_done', (tester) async {
      await pumpApp(tester, setup: TestSetup(recentReels: twoReels()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Newest reel'));
      await tester.pumpAndSettle();

      expect(find.text('Reel ready'), findsOneWidget);
    });

    testWidgets('long_press_offers_delete', (tester) async {
      await pumpApp(tester, setup: TestSetup(recentReels: twoReels()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Older reel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Older reel'), findsNothing);
    });

    testWidgets('urdu_recent_title_reads_right_to_left', (tester) async {
      const title = 'علم دولت ہے';
      await pumpApp(
        tester,
        setup: TestSetup(
          recentReels: [recentReel(folder, title: title, minutesOld: 1)],
        ),
      );
      await tester.pumpAndSettle();

      final shown = tester.widget<Text>(find.text(title));

      expect(shown.textDirection, TextDirection.rtl);
    });

    testWidgets('empty_state_text_when_no_reels', (tester) async {
      await pumpApp(tester);

      expect(
        find.text('Your reels and scripts will appear here.'),
        findsOneWidget,
      );
    });
  });

  group('saved scripts', () {
    late Directory folder;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('home_screen_test');
    });

    tearDown(() => folder.delete(recursive: true));

    testWidgets('home_lists_saved_scripts', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          savedScripts: [savedScript(title: 'Processed video', minutesOld: 1)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Processed video'), findsOneWidget);
    });

    testWidgets('saved_script_row_shows_language_length_and_date', (
      tester,
    ) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          savedScripts: [savedScript(title: 'Processed video', minutesOld: 1)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Script · Urdu (detected) · 6:48 · 2 Nov'),
        findsOneWidget,
      );
    });

    testWidgets('recent_mixes_reels_and_scripts_newest_first', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          recentReels: [
            recentReel(folder, title: 'Older reel', minutesOld: 60),
          ],
          savedScripts: [savedScript(title: 'Newer script', minutesOld: 1)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Newer script')).dy,
        lessThan(tester.getTopLeft(find.text('Older reel')).dy),
      );
    });

    testWidgets('tapping_saved_script_opens_script', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          savedScripts: [savedScript(title: 'Processed video', minutesOld: 1)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Processed video'));
      await tester.pumpAndSettle();

      expect(find.text('Tap the line where your clip starts'), findsOneWidget);
    });

    testWidgets('long_press_deletes_saved_script', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          savedScripts: [savedScript(title: 'Processed video', minutesOld: 1)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Processed video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Processed video'), findsNothing);
    });
  });

  group('fine-tunes to continue', () {
    final savedAt = DateTime(2026, 11, 4, 10);

    testWidgets('a_kept_fine_tune_shows_title_clip_length_and_date', (
      tester,
    ) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          fineTunes: [savedFineTune(title: 'Kept song', savedAt: savedAt)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kept song'), findsOneWidget);
      expect(find.text('Fine-tune · 6.0 s · 4 Nov'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('a_kept_fine_tune_hides_its_script_row', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          savedScripts: [savedScript(title: 'Processed video', minutesOld: 1)],
          fineTunes: [
            savedFineTune(
              videoId: 'video_1',
              title: 'Kept song',
              language: ScriptLanguage.auto,
              savedAt: savedAt,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Processed video'), findsNothing);
      expect(find.text('Kept song'), findsOneWidget);
    });

    testWidgets('long_press_offers_delete_progress', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(fineTunes: [savedFineTune(title: 'Kept song')]),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Kept song'));
      await tester.pumpAndSettle();

      expect(find.text('Delete progress'), findsOneWidget);
    });

    testWidgets('delete_progress_brings_back_the_script_row', (tester) async {
      await pumpApp(
        tester,
        setup: TestSetup(
          savedScripts: [savedScript(title: 'Processed video', minutesOld: 1)],
          fineTunes: [
            savedFineTune(
              videoId: 'video_1',
              title: 'Kept song',
              language: ScriptLanguage.auto,
              savedAt: savedAt,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Kept song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete progress'));
      await tester.pumpAndSettle();

      expect(find.text('Processed video'), findsOneWidget);
      expect(find.text('Kept song'), findsNothing);
    });
  });
}
