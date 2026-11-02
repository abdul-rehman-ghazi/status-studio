import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_background_work_platform.dart';
import '../../../../helpers/pump_app.dart';

/// Settings, scrolled down to "Background work".
Future<void> openSection(
  WidgetTester tester,
  FakeBackgroundWorkPlatform platform,
) async {
  await pumpRoutes(tester, [
    AppRoutes.settings,
  ], setup: TestSetup(backgroundWork: platform));
  await tester.scrollUntilVisible(find.text('Open App info'), 200);
  await tester.pumpAndSettle();
}

/// The "Allow" button in the row for [label].
Finder allowIn(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
  matching: find.text('Allow'),
);

void main() {
  testWidgets('battery_optimised_offers_allow', (tester) async {
    final platform = FakeBackgroundWorkPlatform()..unrestricted = false;

    await openSection(tester, platform);

    expect(allowIn('Battery optimisation'), findsOneWidget);
  });

  testWidgets('allow_battery_asks_android', (tester) async {
    final platform = FakeBackgroundWorkPlatform()..unrestricted = false;
    await openSection(tester, platform);

    await tester.tap(allowIn('Battery optimisation'));
    await tester.pumpAndSettle();

    expect(platform.calls, contains('askToRunUnrestricted'));
  });

  testWidgets('notifications_off_offers_allow', (tester) async {
    final platform = FakeBackgroundWorkPlatform()..notificationsAllowed = false;

    await openSection(tester, platform);

    expect(allowIn('Notifications'), findsOneWidget);
  });

  testWidgets('allowing_notifications_shows_them_on', (tester) async {
    final platform = FakeBackgroundWorkPlatform()..grantsNotifications = true;
    await openSection(tester, platform);

    await tester.tap(allowIn('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('allowed_rows_offer_nothing', (tester) async {
    final platform = FakeBackgroundWorkPlatform()
      ..notificationsAllowed = true
      ..unrestricted = true;

    await openSection(tester, platform);

    expect(find.text('Allow'), findsNothing);
  });

  testWidgets('open_app_info_opens_it', (tester) async {
    final platform = FakeBackgroundWorkPlatform();
    await openSection(tester, platform);

    await tester.tap(find.text('Open App info'));
    await tester.pumpAndSettle();

    expect(platform.calls.last, 'openAppInfo');
  });
}
