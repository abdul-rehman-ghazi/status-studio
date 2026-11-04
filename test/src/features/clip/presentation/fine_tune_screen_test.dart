import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/data/frame_extractor.dart';
import 'package:status_studio/src/features/style/data/subject_detector.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../helpers/fake_clip_preparer.dart';
import '../../../../helpers/fake_follow.dart';
import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/fine_tune_pump.dart';
import '../../../../helpers/fixtures.dart';

Future<void> pumpFineTune(
  WidgetTester tester, {
  VideoPlayerFactory playerFactory = fakePlayerFactory,
  FakeClipSourcePreparer? clipPreparer,
  ReelDraft? draft,
  List<double>? waveformPeaks,
  List<Override> overrides = const [],
}) => pumpFineTuneStep(
  tester,
  AppRoutes.fineTune,
  playerFactory: playerFactory,
  clipPreparer: clipPreparer,
  draft: draft,
  waveformPeaks: waveformPeaks,
  overrides: overrides,
);

/// Scrolls the body to its top, then down to [label], then taps it. Starting
/// from the top finds a label whatever the list has grown to since.
Future<void> tapText(WidgetTester tester, String label) async {
  final body = find.byType(Scrollable).last;
  await tester.drag(body, const Offset(0, 3000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(label), 200, scrollable: body);
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
}

/// The clip as the draft holds it now.
ClipRange clipNow(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
        .read(reelDraftProvider)
        .clip!;

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

  testWidgets('tapping_the_start_time_sets_it_to_the_playhead', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    players.created.single.value = players.created.single.value.copyWith(
      position: fileTime(const Duration(seconds: 25)),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Set start to the playhead'));
    await tester.pump();

    expect(clipNow(tester).start, const Duration(seconds: 25));
  });

  testWidgets('tapping_the_end_time_sets_it_to_the_playhead', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    players.created.single.value = players.created.single.value.copyWith(
      position: fileTime(const Duration(seconds: 45)),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Set end to the playhead'));
    await tester.pump();

    expect(clipNow(tester).end, const Duration(seconds: 45));
  });

  testWidgets('a_tap_that_would_make_the_clip_too_short_changes_nothing', (
    tester,
  ) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    players.created.single.value = players.created.single.value.copyWith(
      position: fileTime(const Duration(seconds: 47)),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Set start to the playhead'));
    await tester.pump();

    expect(clipNow(tester).start, pickedDraft.clip!.start);
  });

  testWidgets('shows_clip_length', (tester) async {
    await pumpFineTune(tester);

    expect(find.text('27.4 s'), findsOneWidget);
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

  testWidgets('the_seek_bar_does_not_colour_the_time_already_played', (
    tester,
  ) async {
    await pumpFineTune(tester);

    final theme = tester.widget<SliderTheme>(
      find
          .ancestor(of: find.byType(Slider), matching: find.byType(SliderTheme))
          .first,
    );

    expect(theme.data.activeTrackColor, Colors.transparent);
  });

  testWidgets('the_seek_bar_moves_between_the_players_reports', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    final player = players.created.single;
    player.value = player.value.copyWith(
      isPlaying: true,
      position: fileTime(const Duration(seconds: 25)),
    );
    await tester.pump();
    final before = tester.widget<Slider>(find.byType(Slider)).value;

    // The player reports nothing for 300 ms, as a real one doesn't for a
    // while; the bar still moves on.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      greaterThan(before + 200),
    );
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

  testWidgets('video_player_is_released_while_lyrics_is_open', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);

    await tester.tap(find.text('Next: lyrics'));
    await tester.pumpAndSettle();

    // Lyrics makes its own player; this step's was the first.
    expect(players.created.first.disposed, isTrue);
  });

  testWidgets('video_player_comes_back_when_lyrics_closes', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    await tester.tap(find.text('Next: lyrics'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(players.created.last.disposed, isFalse);
    expect(players.created.length, 3);
  });

  testWidgets('a_vertical_video_is_capped_in_height', (tester) async {
    await pumpFineTune(tester, playerFactory: portraitPlayerFactory);

    expect(
      tester.getSize(find.byType(VideoPlayer)).height,
      lessThanOrEqualTo(260),
    );
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

  group('frame', () {
    testWidgets('fill_options_hidden_for_16_9', (tester) async {
      await pumpFineTune(tester);

      await tapText(tester, '16:9');

      expect(find.text('Blur background'), findsNothing);
    });

    testWidgets('free_preset_shows_crop_editor', (tester) async {
      await pumpFineTune(tester);

      await tapText(tester, 'Free');

      expect(
        find.text('Drag to move. Drag the corner to resize.'),
        findsOneWidget,
      );
    });

    testWidgets('size_hint_shows_output_size', (tester) async {
      await pumpFineTune(tester);

      await tapText(tester, '4:5');

      expect(
        find.text('Instagram and Facebook posts · 1080 × 1350'),
        findsOneWidget,
      );
    });

    testWidgets('blur_background_hides_keep_in_view', (tester) async {
      await pumpFineTune(tester);

      await tapText(tester, 'Blur background');

      expect(find.text('Keep in view'), findsNothing);
    });
  });

  group('moving crop', () {
    const movingSwitch = 'Move the crop during the clip';

    ReelDraft draftNow(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
            .read(reelDraftProvider);

    CropPath pathNow(WidgetTester tester) => draftNow(tester).frame.cropPath;

    Future<FakeVideoPlayerController> turnOn(WidgetTester tester) async {
      final players = RecordingPlayerFactory();
      await pumpFineTune(tester, playerFactory: players.call);
      await tapText(tester, movingSwitch);
      return players.created.single;
    }

    Future<void> dragCropAt(
      WidgetTester tester,
      FakeVideoPlayerController player,
      Duration videoTime,
    ) async {
      player.value = player.value.copyWith(position: fileTime(videoTime));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('crop-window')),
        const Offset(40, 0),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the_switch_is_offered_for_a_cropped_frame', (tester) async {
      await pumpFineTune(tester);
      await tester.scrollUntilVisible(
        find.text(movingSwitch),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text(movingSwitch), findsOneWidget);
    });

    testWidgets('the_switch_is_hidden_for_16_9', (tester) async {
      await pumpFineTune(tester);
      await tapText(tester, '16:9');

      expect(find.text(movingSwitch), findsNothing);
    });

    testWidgets('turning_it_on_makes_a_keyframe_at_the_clip_start', (
      tester,
    ) async {
      await turnOn(tester);

      expect(pathNow(tester).keyframes.single.time, pickedDraft.clip!.start);
    });

    testWidgets('turning_it_on_shows_the_keyframe_chip', (tester) async {
      await turnOn(tester);

      expect(find.widgetWithText(ChoiceChip, '0:21.4'), findsOneWidget);
    });

    testWidgets('keep_in_view_is_hidden_while_it_moves', (tester) async {
      await turnOn(tester);

      expect(find.text('Keep in view'), findsNothing);
    });

    testWidgets('chips_are_hidden_when_nothing_can_move', (tester) async {
      await turnOn(tester);

      await tapText(tester, '16:9');

      expect(find.widgetWithText(ChoiceChip, '0:21.4'), findsNothing);
    });

    testWidgets('the_switch_stays_so_a_hidden_move_can_be_turned_off', (
      tester,
    ) async {
      await turnOn(tester);

      await tapText(tester, '16:9');

      expect(find.text(movingSwitch), findsOneWidget);
    });

    testWidgets(
      'the_free_crop_editor_cannot_move_the_rectangle_while_it_moves',
      (tester) async {
        await pumpFineTune(tester);
        await tapText(tester, 'Free');
        await tapText(tester, movingSwitch);
        await tester.scrollUntilVisible(
          find.text('Reset'),
          200,
          scrollable: find.byType(Scrollable).last,
        );

        await tester.drag(
          find.byKey(const ValueKey('free-crop-area')),
          const Offset(30, 0),
        );
        await tester.pump();

        expect(draftNow(tester).frame.freeCrop.left, FreeCropRect.initial.left);
      },
    );

    testWidgets('a_drag_writes_one_keyframe_at_the_playhead', (tester) async {
      final player = await turnOn(tester);

      await dragCropAt(tester, player, const Duration(seconds: 35));

      expect(pathNow(tester).keyframes.map((keyframe) => keyframe.time), [
        pickedDraft.clip!.start,
        const Duration(seconds: 35),
      ]);
    });

    testWidgets('a_drag_moves_the_window_to_the_right', (tester) async {
      final player = await turnOn(tester);

      await dragCropAt(tester, player, const Duration(seconds: 35));

      expect(pathNow(tester).keyframes.last.anchor.x, greaterThan(0.5));
    });

    testWidgets('cut_changes_how_the_keyframe_arrives', (tester) async {
      final player = await turnOn(tester);
      await dragCropAt(tester, player, const Duration(seconds: 35));

      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();

      expect(pathNow(tester).keyframes.last.arrival, CropArrival.cut);
    });

    testWidgets('the_first_keyframe_has_no_glide_or_cut', (tester) async {
      await turnOn(tester);

      expect(find.text('Glide'), findsNothing);
    });

    testWidgets('delete_removes_the_selected_keyframe', (tester) async {
      final player = await turnOn(tester);
      await dragCropAt(tester, player, const Duration(seconds: 35));

      await tester.tap(find.byTooltip('Delete keyframe'));
      await tester.pumpAndSettle();

      expect(pathNow(tester).keyframes.length, 1);
    });

    testWidgets('the_only_keyframe_cannot_be_deleted', (tester) async {
      await turnOn(tester);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('a_chip_jumps_the_video_to_its_keyframe', (tester) async {
      final player = await turnOn(tester);
      await dragCropAt(tester, player, const Duration(seconds: 35));
      player.value = player.value.copyWith(position: Duration.zero);

      await tester.tap(find.widgetWithText(ChoiceChip, '0:35.0'));
      await tester.pump();

      expect(player.value.position, fileTime(const Duration(seconds: 35)));
    });

    testWidgets('turning_it_off_removes_the_keyframes', (tester) async {
      final player = await turnOn(tester);
      await dragCropAt(tester, player, const Duration(seconds: 35));

      await tapText(tester, movingSwitch);

      expect(pathNow(tester).isEmpty, isTrue);
    });
  });

  group('follow the person', () {
    const movingSwitch = 'Move the crop during the clip';
    late FakeFrameExtractor extractor;
    late FakeSubjectDetector detector;
    late RecordingPlayerFactory players;

    CropPath pathNow(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
            .read(reelDraftProvider)
            .frame
            .cropPath;

    Future<void> pumpMoving(
      WidgetTester tester, {
      FakeSubjectDetector? faces,
      bool moving = true,
    }) async {
      extractor = FakeFrameExtractor();
      detector = faces ?? FakeSubjectDetector(facesAt: (_) => [centredFace]);
      players = RecordingPlayerFactory();
      await pumpFineTune(
        tester,
        playerFactory: players.call,
        overrides: [
          frameExtractorProvider.overrideWithValue(extractor),
          subjectDetectorProvider.overrideWithValue(() => detector),
        ],
      );
      if (moving) {
        await tapText(tester, movingSwitch);
      }
    }

    Future<void> tapFollow(WidgetTester tester) =>
        tapText(tester, 'Follow the person');

    testWidgets('the_button_shows_while_the_crop_moves', (tester) async {
      await pumpMoving(tester);
      await tester.scrollUntilVisible(
        find.text('Follow the person'),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Runs on your phone; nothing is uploaded.'), findsOne);
    });

    testWidgets('the_button_is_not_shown_while_the_crop_is_fixed', (
      tester,
    ) async {
      await pumpMoving(tester, moving: false);
      await tester.scrollUntilVisible(
        find.text(movingSwitch),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Follow the person'), findsNothing);
    });

    testWidgets('a_run_ends_with_a_snackbar_saying_how_many_keyframes', (
      tester,
    ) async {
      await pumpMoving(tester);

      await tapFollow(tester);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The crop follows the person (1 keyframe). '
          'Drag or tap a chip to adjust.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a_finished_run_goes_to_the_clip_start', (tester) async {
      await pumpMoving(tester);
      final player = players.created.single;
      player.value = player.value.copyWith(
        position: fileTime(const Duration(seconds: 40)),
      );

      await tapFollow(tester);
      await tester.pumpAndSettle();

      expect(player.value.position, fileTime(pickedDraft.clip!.start));
    });

    testWidgets('no_person_shows_the_message_and_changes_nothing', (
      tester,
    ) async {
      await pumpMoving(tester, faces: FakeSubjectDetector());
      final before = pathNow(tester);

      await tapFollow(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('No person found in this clip. The crop stays where it is.'),
        findsOneWidget,
      );
      expect(pathNow(tester), before);
    });

    testWidgets('a_failure_shows_its_message', (tester) async {
      await pumpMoving(
        tester,
        faces: FakeSubjectDetector(failure: Exception('model')),
      );

      await tapFollow(tester);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't follow the person. Try again."), findsOne);
    });

    testWidgets('a_run_shows_its_progress_and_a_cancel', (tester) async {
      await pumpMoving(
        tester,
        faces: FakeSubjectDetector()..gate = Completer(),
      );

      await tapFollow(tester);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Finding the person'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancel_brings_the_button_back_and_changes_nothing', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pumpMoving(tester, faces: FakeSubjectDetector()..gate = gate);
      final before = pathNow(tester);
      await tapFollow(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Cancel'));
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Follow the person'), findsOneWidget);
      expect(pathNow(tester), before);
    });

    group('with two people', () {
      Future<void> pumpTwoPeople(WidgetTester tester) => pumpMoving(
        tester,
        faces: FakeSubjectDetector(facesAt: (_) => [leftFace, rightFace]),
      );

      Future<void> askWhom(WidgetTester tester) async {
        await tapFollow(tester);
        await tester.pumpAndSettle();
      }

      testWidgets('the_chooser_opens', (tester) async {
        await pumpTwoPeople(tester);

        await askWhom(tester);

        expect(find.text('Who should the crop follow?'), findsOneWidget);
      });

      testWidgets('tapping_a_face_ends_with_the_snackbar', (tester) async {
        await pumpTwoPeople(tester);
        await askWhom(tester);
        final picture = tester.getRect(find.byKey(const Key('person-picture')));

        await tester.tapAt(
          picture.topLeft + Offset(picture.width * 0.75, picture.height * 0.4),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'The crop follows the person (1 keyframe). '
            'Drag or tap a chip to adjust.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('tapping_a_face_closes_the_chooser', (tester) async {
        await pumpTwoPeople(tester);
        await askWhom(tester);
        final picture = tester.getRect(find.byKey(const Key('person-picture')));

        await tester.tapAt(
          picture.topLeft + Offset(picture.width * 0.75, picture.height * 0.4),
        );
        await tester.pumpAndSettle();

        expect(find.text('Who should the crop follow?'), findsNothing);
      });

      testWidgets('choose_for_me_ends_with_the_snackbar', (tester) async {
        await pumpTwoPeople(tester);
        await askWhom(tester);

        await tester.tap(find.text('Choose for me'));
        await tester.pumpAndSettle();

        expect(find.textContaining('The crop follows the person'), findsOne);
      });

      testWidgets('cancel_changes_nothing_and_brings_the_button_back', (
        tester,
      ) async {
        await pumpTwoPeople(tester);
        final before = pathNow(tester);
        await askWhom(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(pathNow(tester), before);
        expect(find.text('Follow the person'), findsOneWidget);
      });

      testWidgets('dismissing_the_chooser_changes_nothing_and_deletes_frames', (
        tester,
      ) async {
        await pumpTwoPeople(tester);
        final before = pathNow(tester);
        await askWhom(tester);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        // The delete is real file work whose steps run in this test's fake
        // clock, so let real time pass and pump between the steps.
        for (var tries = 0; tries < 20; tries++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }

        expect(pathNow(tester), before);
        expect(find.text('Follow the person'), findsOneWidget);
        expect(extractor.made!.existsSync(), isFalse);
      });
    });

    group('with keyframes of the users own', () {
      Future<void> addSecondKeyframe(WidgetTester tester) async {
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
            .read(reelDraftProvider.notifier)
            .moveCropTo(
              pickedDraft.clip!.start + const Duration(seconds: 5),
              const CropAnchor(x: 1, y: 0.5),
            );
        await tester.pump();
      }

      testWidgets('replacing_is_asked_first', (tester) async {
        await pumpMoving(tester);
        await addSecondKeyframe(tester);

        await tapFollow(tester);
        await tester.pumpAndSettle();

        expect(find.text('Replace your crop keyframes?'), findsOneWidget);
      });

      testWidgets('keep_does_not_run', (tester) async {
        await pumpMoving(tester);
        await addSecondKeyframe(tester);
        await tapFollow(tester);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Keep'));
        await tester.pumpAndSettle();

        expect(extractor.made, isNull);
        expect(pathNow(tester).keyframes.length, 2);
      });

      testWidgets('replace_runs_and_replaces', (tester) async {
        await pumpMoving(tester);
        await addSecondKeyframe(tester);
        await tapFollow(tester);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Replace'));
        await tester.pumpAndSettle();

        expect(pathNow(tester).keyframes.length, 1);
      });
    });

    testWidgets('one_keyframe_is_replaced_without_asking', (tester) async {
      await pumpMoving(tester);

      await tapFollow(tester);
      await tester.pumpAndSettle();

      expect(find.text('Replace your crop keyframes?'), findsNothing);
    });

    testWidgets('opening_lyrics_cancels_a_run', (tester) async {
      final gate = Completer<void>();
      await pumpMoving(tester, faces: FakeSubjectDetector()..gate = gate);
      final before = pathNow(tester);
      await tapFollow(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Next: lyrics'));
      gate.complete();
      await tester.pumpAndSettle();

      expect(extractor.handle!.isCancelled, isTrue);
      expect(pathNow(tester), before);
    });
  });
}
