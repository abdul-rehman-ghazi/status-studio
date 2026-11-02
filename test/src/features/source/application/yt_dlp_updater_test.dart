import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/source/application/yt_dlp_updater.dart';

import '../../../../helpers/fake_yt_dlp.dart';

void main() {
  final monday = DateTime.utc(2026, 11, 2, 9);
  late FakeYtDlp ytDlp;
  late YtDlpUpdater updater;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    ytDlp = FakeYtDlp();
    updater = YtDlpUpdater(ytDlp, SharedPreferencesAsync());
  });

  test('first_start_updates', () async {
    await updater.updateIfDue(monday);

    expect(ytDlp.updates, 1);
  });

  test('update_skipped_within_a_week', () async {
    await updater.updateIfDue(monday);

    await updater.updateIfDue(monday.add(const Duration(days: 6)));

    expect(ytDlp.updates, 1);
  });

  test('update_runs_when_a_week_has_passed', () async {
    await updater.updateIfDue(monday);

    await updater.updateIfDue(monday.add(const Duration(days: 7)));

    expect(ytDlp.updates, 2);
  });

  test('update_now_counts_as_the_weekly_update', () async {
    await updater.updateNow(monday);

    await updater.updateIfDue(monday.add(const Duration(days: 1)));

    expect(ytDlp.updates, 1);
  });
}
