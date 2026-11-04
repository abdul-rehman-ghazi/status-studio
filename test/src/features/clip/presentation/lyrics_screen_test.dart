import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/presentation/clip_lines_list.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/presentation/reel_stage.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/fine_tune_pump.dart';
import '../../../../helpers/fixtures.dart';

Future<void> pumpLyrics(
  WidgetTester tester, {
  VideoPlayerFactory playerFactory = fakePlayerFactory,
  ReelDraft? draft,
  ScriptEditingService? scriptEditing,
}) => pumpFineTuneStep(
  tester,
  AppRoutes.lyrics,
  playerFactory: playerFactory,
  draft: draft,
  scriptEditing: scriptEditing,
);

void main() {
  group('only the clip', () {
    final clip = pickedDraft.clip!;

    testWidgets('the_player_starts_at_the_clip_start', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);

      expect(players.created.single.value.position, fileTime(clip.start));
    });

    testWidgets('the_seek_bar_covers_only_the_clip', (tester) async {
      await pumpLyrics(tester);

      final slider = tester.widget<Slider>(find.byType(Slider));

      expect(
        (slider.min, slider.max),
        (
          fileTime(clip.start).inMilliseconds.toDouble(),
          fileTime(clip.end).inMilliseconds.toDouble(),
        ),
      );
    });

    testWidgets('playback_pauses_at_the_clip_end', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      final player = players.created.single;

      player.value = player.value.copyWith(position: fileTime(clip.end));
      await tester.pump();

      expect(player.value.isPlaying, isFalse);
    });

    testWidgets('playing_from_the_end_starts_again_at_the_start', (
      tester,
    ) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);
      final player = players.created.single;
      player.value = player.value.copyWith(position: fileTime(clip.end));

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();

      expect(player.value.position, fileTime(clip.start));
    });

    testWidgets('there_is_no_play_clip_button', (tester) async {
      await pumpLyrics(tester);

      expect(find.text('Play clip'), findsNothing);
    });
  });

  group('video with the lyrics', () {
    testWidgets('shows_the_reel_not_the_bare_video', (tester) async {
      await pumpLyrics(tester);

      expect(find.byType(ReelStage), findsOneWidget);
    });

    testWidgets('the_first_line_shows_on_the_video_from_the_clip_start', (
      tester,
    ) async {
      await pumpLyrics(tester);

      // In the list and, the clip starting where it begins, on the video.
      expect(find.text(sampleTranscript.lines[1].text), findsNWidgets(2));
    });

    testWidgets('the_line_due_shows_on_the_video', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);

      players.created.single.value = players.created.single.value.copyWith(
        position: fileTime(const Duration(seconds: 25)),
      );
      await tester.pump();

      // In the list and on the video.
      expect(find.text(sampleTranscript.lines[1].text), findsNWidgets(2));
    });

    testWidgets('the_line_leaves_the_video_between_lines', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);

      // Line 1 ends at 30.0 s and line 2 starts at 30.8 s.
      players.created.single.value = players.created.single.value.copyWith(
        position: fileTime(const Duration(milliseconds: 30400)),
      );
      await tester.pump();

      expect(find.text(sampleTranscript.lines[1].text), findsOneWidget);
    });
  });

  group('lines', () {
    String textOf(int index) => sampleTranscript.lines[index].text;

    /// The line's row in the list; a line due also shows on the video.
    Finder rowOf(int index) => find.descendant(
      of: find.byType(ClipLinesList),
      matching: find.text(textOf(index)),
    );

    ReelDraft draftNow(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
            .read(reelDraftProvider);

    Future<void> reveal(WidgetTester tester, int index) async {
      final line = rowOf(index);
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

    testWidgets('tap_while_paused_seeks_to_the_line', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);
      await reveal(tester, 2);

      await tester.tap(rowOf(2));
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
      await pumpLyrics(tester, playerFactory: players.call);
      await reveal(tester, 2);
      await playAt(tester, players.created.single, const Duration(seconds: 33));

      await tester.tap(rowOf(2));
      await tester.pump();

      expect(
        draftNow(tester).transcript!.lines[2].start.inMilliseconds,
        closeTo(33000, 300),
      );
    });

    testWidgets('highlight_marks_the_playing_line', (tester) async {
      final handle = tester.ensureSemantics();
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);
      await reveal(tester, 1);

      await playAt(tester, players.created.single, const Duration(seconds: 25));

      expect(
        tester.getSemantics(find.byKey(const ValueKey('line-1'))),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('edit_changes_the_lines_text', (tester) async {
      await pumpLyrics(tester);
      await reveal(tester, 2);

      await tester.tap(find.byTooltip('Edit line').at(1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'نیا مصرعہ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(draftNow(tester).transcript!.lines[2].text, 'نیا مصرعہ');
    });

    testWidgets('delete_removes_the_line', (tester) async {
      await pumpLyrics(tester);
      await reveal(tester, 2);

      await tester.tap(find.byTooltip('Delete line').at(1));
      await tester.pump();

      expect(draftNow(tester).transcript!.lines.length, 8);
    });

    testWidgets('delete_is_off_for_the_only_picked_line', (tester) async {
      final onePicked = pickedDraft.withSelection(const RangeSelected(2, 2));
      await pumpLyrics(tester, draft: onePicked);
      await reveal(tester, 2);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline).at(0),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('add_line_is_off_outside_the_clip', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);
      await tester.scrollUntilVisible(
        find.text('Add line'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      players.created.single.value = players.created.single.value.copyWith(
        position: fileTime(const Duration(seconds: 15)),
      );
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Add line'),
          matching: find.byType(TextButton),
        ),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('add_line_inserts_at_the_playhead', (tester) async {
      final players = RecordingPlayerFactory();
      await pumpLyrics(tester, playerFactory: players.call);
      await tester.scrollUntilVisible(
        find.text('Add line'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Add line'));
      await tester.pumpAndSettle();
      players.created.single.value = players.created.single.value.copyWith(
        position: fileTime(const Duration(seconds: 35)),
      );
      await tester.pump();

      await tester.tap(find.text('Add line'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'نئی سطر');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(draftNow(tester).transcript!.lines[3].text, 'نئی سطر');
    });

    testWidgets('dragging_a_line_down_moves_the_next_text_up', (tester) async {
      await pumpLyrics(tester);
      await reveal(tester, 2);

      await tester.ensureVisible(find.byTooltip('Move line').at(0));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byTooltip('Move line').at(0),
        const Offset(0, 150),
      );
      await tester.pumpAndSettle();

      expect(draftNow(tester).transcript!.lines[1].text, textOf(2));
    });
  });

  group('saving edits', () {
    Future<void> editFirstShownLine(WidgetTester tester) async {
      final line = find.descendant(
        of: find.byType(ClipLinesList),
        matching: find.text(sampleTranscript.lines[2].text),
      );
      await tester.ensureVisible(line);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete line').at(1));
      await tester.pump();
    }

    testWidgets('an_edit_is_saved_after_a_second_without_edits', (
      tester,
    ) async {
      final editing = RecordingScriptEditingService();
      await pumpLyrics(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(editing.saved.single.lines.length, 8);
    });

    testWidgets('nothing_is_saved_before_the_pause', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpLyrics(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      await tester.pump(const Duration(milliseconds: 900));

      expect(editing.saved, isEmpty);
    });

    testWidgets('leaving_the_screen_saves_a_pending_edit', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpLyrics(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(editing.saved.single.lines.length, 8);
    });

    testWidgets('going_to_the_background_saves_a_pending_edit', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpLyrics(tester, scriptEditing: editing);
      await editFirstShownLine(tester);

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      expect(editing.saved.single.lines.length, 8);
    });

    testWidgets('lines_still_streaming_in_save_nothing', (tester) async {
      final editing = RecordingScriptEditingService();
      await pumpLyrics(tester, scriptEditing: editing);
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
      await pumpLyrics(tester, scriptEditing: editing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(editing.saved, isEmpty);
    });
  });
}
