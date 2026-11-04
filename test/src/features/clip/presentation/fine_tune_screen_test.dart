import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_clip_preparer.dart';
import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/fine_tune_pump.dart';
import '../../../../helpers/fixtures.dart';

Future<void> pumpFineTune(
  WidgetTester tester, {
  VideoPlayerFactory playerFactory = fakePlayerFactory,
  FakeClipSourcePreparer? clipPreparer,
  ReelDraft? draft,
  List<double>? waveformPeaks,
}) => pumpFineTuneStep(
  tester,
  AppRoutes.fineTune,
  playerFactory: playerFactory,
  clipPreparer: clipPreparer,
  draft: draft,
  waveformPeaks: waveformPeaks,
);

/// Scrolls [label] into view, then taps it.
Future<void> tapText(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200);
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
}

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

  testWidgets('playback_pauses_when_lyrics_opens', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    await tester.tap(find.text('Play clip'));
    await tester.pump();

    await tester.tap(find.text('Next: lyrics'));
    await tester.pumpAndSettle();

    // Lyrics makes its own player; this step's was the first.
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
}
