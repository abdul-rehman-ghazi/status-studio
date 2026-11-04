import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/export/presentation/reel_player.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../helpers/fake_reel_actions.dart';
import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/pump_app.dart';
import '../../../../helpers/recent_reels.dart';

void main() {
  late Directory folder;
  late RecentReel reel;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('done_screen_test');
    reel = recentReel(folder, title: 'Knowledge is wealth', minutesOld: 1);
  });

  tearDown(() => folder.delete(recursive: true));

  Future<void> pumpDone(WidgetTester tester, FakeReelActions actions) =>
      pumpRoutes(tester, [
        AppRoutes.doneFor(reel.id),
      ], setup: TestSetup(reelActions: actions, recentReels: [reel]));

  Future<void> pumpDoneWithPlayer(
    WidgetTester tester,
    VideoPlayerFactory playerFactory,
  ) => pumpRoutes(
    tester,
    [AppRoutes.doneFor(reel.id)],
    setup: TestSetup(
      reelActions: FakeReelActions(),
      recentReels: [reel],
      playerFactory: playerFactory,
    ),
  );

  testWidgets('done_plays_the_exported_file', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpDoneWithPlayer(tester, players.call);

    expect(find.byType(VideoPlayer), findsOneWidget);
  });

  testWidgets('tapping_the_reel_plays_it', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpDoneWithPlayer(tester, players.call);

    await tester.tap(find.byType(ReelPlayer));
    await tester.pump();

    expect(players.created.single.value.isPlaying, isTrue);
  });

  testWidgets('tapping_a_playing_reel_pauses_it', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpDoneWithPlayer(tester, players.call);

    await tester.tap(find.byType(ReelPlayer));
    await tester.pump();
    await tester.tap(find.byType(ReelPlayer));
    await tester.pump();

    expect(players.created.single.value.isPlaying, isFalse);
  });

  testWidgets('a_finished_reel_goes_back_to_the_start', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpDoneWithPlayer(tester, players.call);
    final player = players.created.single;

    player.value = player.value.copyWith(
      position: player.value.duration,
      isCompleted: true,
    );
    await tester.pump();

    expect(player.value.position, Duration.zero);
  });

  testWidgets('a_file_that_will_not_play_keeps_the_thumbnail', (tester) async {
    await pumpDoneWithPlayer(tester, brokenPlayerFactory);

    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('leaving_done_disposes_the_player', (tester) async {
    final players = RecordingPlayerFactory();
    await pumpDoneWithPlayer(tester, players.call);

    await tester.tap(find.text('Make another'));
    await tester.pumpAndSettle();

    expect(players.created.single.disposed, isTrue);
  });

  testWidgets('done_shows_size_length_and_format', (tester) async {
    await pumpDone(tester, FakeReelActions());

    expect(find.text('1080 × 1920 · 27.4 s · MP4'), findsOneWidget);
  });

  testWidgets('save_shows_saved_state', (tester) async {
    await pumpDone(tester, FakeReelActions());

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('double_tap_on_save_saves_once', (tester) async {
    final actions = FakeReelActions()..saveGate = Completer<void>();
    await pumpDone(tester, actions);

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    actions.saveGate!.complete();
    await tester.pumpAndSettle();

    expect(actions.saved, hasLength(1));
  });

  testWidgets('save_on_a_full_phone_says_not_enough_space', (tester) async {
    final actions = FakeReelActions()
      ..saveFailure = const InsufficientStorageException('No space');
    await pumpDone(tester, actions);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Not enough space on your phone.'), findsOneWidget);
  });

  testWidgets('failed_share_says_so', (tester) async {
    final actions = FakeReelActions()
      ..shareFailure = PlatformException(code: 'Share failed');
    await pumpDone(tester, actions);

    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
  });

  testWidgets('save_without_access_shows_permission_message', (tester) async {
    await pumpDone(tester, FakeReelActions(denied: true));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      find.text('Allow Photos access in Settings to save reels.'),
      findsOneWidget,
    );
  });

  testWidgets('open_settings_after_denied_save', (tester) async {
    final actions = FakeReelActions(denied: true);
    await pumpDone(tester, actions);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open settings'));
    await tester.pump();

    expect(actions.settingsOpened, 1);
  });

  testWidgets('share_calls_share_with_video_path', (tester) async {
    final actions = FakeReelActions();
    await pumpDone(tester, actions);

    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(actions.shared, [reel.videoPath]);
  });

  testWidgets('missing_reel_says_so', (tester) async {
    await pumpRoutes(tester, [AppRoutes.doneFor('gone')]);

    expect(find.text('This reel is no longer on your phone.'), findsOneWidget);
  });
}
