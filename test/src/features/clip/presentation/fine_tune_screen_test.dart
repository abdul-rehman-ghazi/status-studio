import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

Future<void> pumpFineTune(
  WidgetTester tester, {
  VideoPlayerFactory playerFactory = fakePlayerFactory,
  FakeVideoSource videoSource = const FakeVideoSource(),
}) => pumpRoutes(
  tester,
  [AppRoutes.fineTune],
  setup: TestSetup(
    overrides: [draftOverride(pickedDraft)],
    videoSource: videoSource,
    playerFactory: playerFactory,
  ),
);

/// Reports 40 % and then never finishes.
class StalledVideoSource extends FakeVideoSource {
  const StalledVideoSource();

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) {
    onProgress(0.4);
    return Completer<File>().future;
  }
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

  testWidgets('lists_the_lines_in_the_clip', (tester) async {
    await pumpFineTune(tester);

    expect(find.text('محنت کامیابی کی کنجی ہے'), findsOneWidget);
  });

  testWidgets('preparing_video_shows_progress', (tester) async {
    await pumpFineTune(tester, videoSource: const StalledVideoSource());

    expect(find.text('Preparing video… 40 %'), findsOneWidget);
  });

  testWidgets('play_starts_at_clip_start', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);

    await tester.tap(find.byTooltip('Play clip'));
    await tester.pump();

    expect(players.created.single.value.position, pickedDraft.clip!.start);
  });

  testWidgets('playback_pauses_at_clip_end', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpFineTune(tester, playerFactory: players.call);
    await tester.tap(find.byTooltip('Play clip'));
    await tester.pump();
    final player = players.created.single;

    player.value = player.value.copyWith(position: pickedDraft.clip!.end);
    await tester.pump();

    expect(player.value.isPlaying, isFalse);
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
    await tester.tap(find.byTooltip('Play clip'));
    await tester.pump();

    await tester.tap(find.text('Next: frame & caption'));
    await tester.pumpAndSettle();

    expect(players.created.single.value.isPlaying, isFalse);
  });

  testWidgets('unplayable_source_shows_message', (tester) async {
    await pumpFineTune(tester, playerFactory: brokenPlayerFactory);

    expect(find.text("Couldn't play this video."), findsOneWidget);
  });
}
