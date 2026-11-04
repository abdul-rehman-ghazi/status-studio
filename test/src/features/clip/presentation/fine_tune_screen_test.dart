import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_clip_preparer.dart';
import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

/// Remembers what Fine-tune saves instead of writing files.
class RecordingScriptEditingService extends ScriptEditingService {
  RecordingScriptEditingService()
    : super(
        store: Future.value(
          TranscriptStore(
            Directory.systemTemp.createTempSync('fine_tune'),
            clock: DateTime.now,
          ),
        ),
      );

  final saved = <Transcript>[];

  @override
  Future<void> saveCorrected(
    SourceVideo video,
    ScriptLanguage language,
    Transcript corrected,
  ) async => saved.add(corrected);
}

Future<void> pumpFineTune(
  WidgetTester tester, {
  VideoPlayerFactory playerFactory = fakePlayerFactory,
  FakeClipSourcePreparer? clipPreparer,
  ReelDraft? draft,
  List<double>? waveformPeaks,
  ScriptEditingService? scriptEditing,
}) => pumpRoutes(
  tester,
  [AppRoutes.fineTune],
  setup: TestSetup(
    overrides: [
      draftOverride(draft ?? pickedDraft),
      scriptEditingServiceProvider.overrideWithValue(
        scriptEditing ?? RecordingScriptEditingService(),
      ),
    ],
    playerFactory: playerFactory,
    clipPreparer: clipPreparer,
    waveformPeaks: waveformPeaks,
  ),
);

/// The fake clip's window starts 5 s before the clip, so its file time is
/// video time minus that start.
Duration fileTime(Duration videoTime) =>
    videoTime - (pickedDraft.clip!.start - const Duration(seconds: 5));

void main() {
  testWidgets('nudge_start_updates_label', (tester) async {
    await pumpFineTune(tester);

    await tester.tap(find.bySemanticsLabel('Start half a second earlier'));
    await tester.pump();

    expect(find.text('0:20.9'), findsOneWidget);
  });

  testWidgets('nudge_end_later_updates_label', (tester) async {
    await pumpFineTune(tester);

    await tester.tap(find.bySemanticsLabel('End half a second later'));
    await tester.pump();

    expect(find.text('0:49.3'), findsOneWidget);
  });

  testWidgets('shows_clip_length', (tester) async {
    await pumpFineTune(tester);

    expect(find.text('27.4 s'), findsOneWidget);
  });

  testWidgets('lists_the_lines_in_the_clip', (tester) async {
    await pumpFineTune(tester);

    await tester.scrollUntilVisible(find.text('محنت کامیابی کی کنجی ہے'), 200);

    expect(find.text('محنت کامیابی کی کنجی ہے'), findsOneWidget);
  });

  testWidgets('downloading_clip_shows_progress', (tester) async {
    await pumpFineTune(
      tester,
      clipPreparer: FakeClipSourcePreparer(stalled: true),
    );

    expect(find.text('Downloading clip… 40 %'), findsOneWidget);
  });

  testWidgets('fine_tune_prepares_clip_on_open', (tester) async {
    final preparer = FakeClipSourcePreparer();

    await pumpFineTune(tester, clipPreparer: preparer);

    expect(preparer.calls, 1);
  });

  testWidgets('nudge_inside_window_does_not_redownload', (tester) async {
    final preparer = FakeClipSourcePreparer();
    await pumpFineTune(tester, clipPreparer: preparer);

    await tester.tap(find.bySemanticsLabel('End half a second later'));
    await tester.pumpAndSettle();

    expect(preparer.calls, 1);
  });

  testWidgets('player_seeks_relative_to_offset', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);

    await tester.tap(find.text('Play clip'));
    await tester.pump();

    expect(players.created.single.value.position, const Duration(seconds: 5));
  });

  testWidgets('playback_continues_past_clip_end', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    await tester.tap(find.text('Play clip'));
    await tester.pump();
    final player = players.created.single;

    player.value = player.value.copyWith(
      position: fileTime(pickedDraft.clip!.end),
    );
    await tester.pump();

    expect(player.value.isPlaying, isTrue);
  });

  testWidgets('play_button_pauses_a_playing_clip', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    expect(players.created.single.value.isPlaying, isFalse);
  });

  testWidgets('play_button_resumes_where_it_paused', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    final player = players.created.single;
    player.value = player.value.copyWith(position: const Duration(seconds: 12));

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    expect(player.value.position, const Duration(seconds: 12));
  });

  testWidgets('seek_bar_moves_the_player', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);

    await tester.tap(find.byType(Slider));
    await tester.pump();

    expect(players.created.single.value.position, greaterThan(Duration.zero));
  });

  testWidgets('player_disposed_when_screen_closes', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(players.created.single.disposed, isTrue);
  });

  testWidgets('playback_pauses_when_style_opens', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    await tester.tap(find.text('Play clip'));
    await tester.pump();

    await tester.tap(find.text('Next: frame & caption'));
    await tester.pumpAndSettle();

    // Style's preview makes its own player; Fine-tune's was the first.
    expect(players.created.first.value.isPlaying, isFalse);
  });

  testWidgets('unplayable_source_shows_message', (tester) async {
    await pumpFineTune(tester, playerFactory: brokenPlayerFactory);

    expect(find.text("Couldn't play this video."), findsOneWidget);
  });

  testWidgets('fine_tune_shows_warning_for_long_clip', (tester) async {
    final longClip = pickedDraft.copyWith(
      clip: const ClipRange(
        start: Duration(seconds: 20),
        end: Duration(seconds: 90),
      ),
    );

    await pumpFineTune(tester, draft: longClip);

    expect(
      find.text('Longer than 60 s. WhatsApp Status may cut it.'),
      findsOneWidget,
    );
  });

  testWidgets('fine_tune_shows_waveform_when_peaks_ready', (tester) async {
    await pumpFineTune(tester, waveformPeaks: List.filled(60, 0.5));

    expect(find.byType(WaveformView), findsOneWidget);
  });

  group('lines', () {
    String textOf(int index) => sampleTranscript.lines[index].text;

    ReelDraft draftNow(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
            .read(reelDraftProvider);

    Future<void> reveal(WidgetTester tester, int index) async {
      final line = find.text(textOf(index));
      await tester.scrollUntilVisible(line, 200);
      await tester.ensureVisible(line);
      await tester.pumpAndSettle();
    }

    Future<void> playAt(
      WidgetTester tester,
      FakeVideoPlayerController player,
      Duration videoTime,
    ) async {
      player.value = player.value.copyWith(
        isPlaying: true,
        position: fileTime(videoTime),
      );
      await tester.pump();
    }

    testWidgets('lists_lines_around_the_clip_and_no_others', (tester) async {
      await pumpFineTune(tester);
      await reveal(tester, 4);

      expect(find.text(textOf(5)), findsNothing);
    });

    testWidgets('lists_a_line_before_the_clip', (tester) async {
      await pumpFineTune(tester);

      await reveal(tester, 0);

      expect(find.text(textOf(0)), findsOneWidget);
    });

    testWidgets('tap_while_paused_seeks_to_the_line', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpFineTune(tester, playerFactory: players.call);
      await reveal(tester, 2);

      await tester.tap(find.text(textOf(2)));
      await tester.pump();

      expect(
        players.created.single.value.position,
        fileTime(sampleTranscript.lines[2].start),
      );
    });

    testWidgets('tap_while_playing_starts_the_line_at_the_playhead', (
      tester,
    ) async {
      final players = RecordingPlayerFactory();
      await pumpFineTune(tester, playerFactory: players.call);
      await reveal(tester, 2);
      await playAt(tester, players.created.single, const Duration(seconds: 33));

      await tester.tap(find.text(textOf(2)));
      await tester.pump();

      expect(
        draftNow(tester).transcript!.lines[2].start.inMilliseconds,
        closeTo(33000, 300),
      );
    });

    testWidgets('highlight_marks_the_playing_line', (tester) async {
      final handle = tester.ensureSemantics();
      final players = RecordingPlayerFactory();
      await pumpFineTune(tester, playerFactory: players.call);
      await reveal(tester, 1);

      await playAt(tester, players.created.single, const Duration(seconds: 25));

      expect(
        tester.getSemantics(find.byKey(const ValueKey('line-1'))),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('edit_changes_the_lines_text', (tester) async {
      await pumpFineTune(tester);
      await reveal(tester, 2);

      await tester.tap(find.byTooltip('Edit line').at(2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'نیا مصرعہ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(draftNow(tester).transcript!.lines[2].text, 'نیا مصرعہ');
    });

    testWidgets('delete_removes_the_line', (tester) async {
      await pumpFineTune(tester);
      await reveal(tester, 2);

      await tester.tap(find.byTooltip('Delete line').at(2));
      await tester.pump();

      expect(draftNow(tester).transcript!.lines.length, 8);
    });

    testWidgets('delete_is_off_for_the_only_picked_line', (tester) async {
      final onePicked = pickedDraft.withSelection(const RangeSelected(2, 2));
      await pumpFineTune(tester, draft: onePicked);
      await reveal(tester, 2);

      // Line 2's window starts at line 1, so line 2 is the second row.
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline).at(1),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('add_line_inserts_at_the_playhead', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpFineTune(tester, playerFactory: players.call);
      await tester.scrollUntilVisible(find.text('Add line'), 200);
      await tester.ensureVisible(find.text('Add line'));
      await tester.pumpAndSettle();
      players.created.single.value = players.created.single.value.copyWith(
        position: fileTime(const Duration(seconds: 35)),
      );

      await tester.tap(find.text('Add line'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'نئی سطر');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(draftNow(tester).transcript!.lines[3].text, 'نئی سطر');
    });

    testWidgets('dragging_a_line_down_moves_the_next_text_up', (tester) async {
      await pumpFineTune(tester);
      await reveal(tester, 2);

      await tester.drag(
        find.byTooltip('Move line').at(1),
        const Offset(0, 150),
      );
      await tester.pumpAndSettle();

      expect(draftNow(tester).transcript!.lines[1].text, textOf(2));
    });
  });

  group('saving edits', () {
    Future<void> editFirstShownLine(WidgetTester tester) async {
      final line = find.text(sampleTranscript.lines[2].text);
      await tester.scrollUntilVisible(line, 200);
      await tester.ensureVisible(line);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete line').at(2));
      await tester.pump();
    }

    testWidgets('an_edit_is_saved_after_a_second_without_edits', (
      tester,
    ) async {
      final editing = RecordingScriptEditingService();
      await pumpFineTune(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(editing.saved.single.lines.length, 8);
    });

    testWidgets('nothing_is_saved_before_the_pause', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpFineTune(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      await tester.pump(const Duration(milliseconds: 900));

      expect(editing.saved, isEmpty);
    });

    testWidgets('leaving_the_screen_saves_a_pending_edit', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpFineTune(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(editing.saved.single.lines.length, 8);
    });

    testWidgets('lines_still_streaming_in_save_nothing', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpFineTune(tester, scriptEditing: editing);
      ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
          .read(reelDraftProvider.notifier)
          .growTranscript(
            sampleTranscript.copyWith(
              lines: [...sampleTranscript.lines, sampleTranscript.lines.last],
            ),
          );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(editing.saved, isEmpty);
    });

    testWidgets('leaving_without_edits_saves_nothing', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpFineTune(tester, scriptEditing: editing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(editing.saved, isEmpty);
    });
  });
}
