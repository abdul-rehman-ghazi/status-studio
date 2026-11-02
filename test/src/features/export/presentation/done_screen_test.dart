import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_reel_actions.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

const videoPath = '/files/reels/reel.mp4';

Future<void> pumpDone(WidgetTester tester, FakeReelActions actions) =>
    pumpRoutes(
      tester,
      [AppRoutes.doneFor(videoPath)],
      setup: TestSetup(
        overrides: [draftOverride(pickedDraft)],
        reelActions: actions,
      ),
    );

void main() {
  testWidgets('save_shows_saved_state', (tester) async {
    final actions = FakeReelActions();
    await pumpDone(tester, actions);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
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

    expect(actions.shared, [videoPath]);
  });
}
