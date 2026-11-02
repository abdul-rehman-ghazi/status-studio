import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/background/application/background_access.dart';

import '../../../../helpers/fake_background_work_platform.dart';

void main() {
  late FakeBackgroundWorkPlatform platform;
  late BackgroundAccess access;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = FakeBackgroundWorkPlatform();
    access = BackgroundAccess(platform, SharedPreferencesAsync());
  });

  test('asks_for_notifications_then_battery', () async {
    await access.askOnce();

    expect(platform.calls, ['requestNotifications', 'askToRunUnrestricted']);
  });

  test('asks_only_the_first_time', () async {
    await access.askOnce();
    platform.calls.clear();

    await access.askOnce();

    expect(platform.calls, isEmpty);
  });

  test('skips_battery_request_when_already_exempt', () async {
    platform.unrestricted = true;

    await access.askOnce();

    expect(platform.calls, isNot(contains('askToRunUnrestricted')));
  });

  test('status_reports_notifications_and_battery', () async {
    platform
      ..notificationsAllowed = true
      ..unrestricted = false;

    final status = await access.status();

    expect(status, (notifications: true, unrestricted: false));
  });

  test('refused_notifications_open_app_info', () async {
    platform.grantsNotifications = false;

    await access.allowNotifications();

    expect(platform.calls.last, 'openAppInfo');
  });

  test('granted_notifications_stay_in_the_app', () async {
    platform.grantsNotifications = true;

    await access.allowNotifications();

    expect(platform.calls, isNot(contains('openAppInfo')));
  });
}
