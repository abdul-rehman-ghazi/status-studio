import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_reel_actions.dart';
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
