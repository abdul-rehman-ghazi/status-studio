import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/background/application/background_access.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';

import '../../../../helpers/fake_background_work_platform.dart';

const writing = ProgressNotice(title: 'Writing', text: 'Video', percent: 10);
const writingMore = ProgressNotice(
  title: 'Writing',
  text: 'Video',
  percent: 20,
);
const rendering = ProgressNotice(title: 'Rendering', text: 'Video', percent: 5);
const ready = ResultNotice(title: 'Script ready', text: 'Video');

void main() {
  late FakeBackgroundWorkPlatform platform;
  late BackgroundWork work;
  var appIsVisible = false;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = FakeBackgroundWorkPlatform();
    appIsVisible = false;
    work = BackgroundWork((
      platform: platform,
      access: BackgroundAccess(platform, SharedPreferencesAsync()),
      isAppVisible: () => appIsVisible,
    ));
  });

  List<String> serviceCalls() => [
    for (final call in platform.calls)
      if (call == 'show' || call == 'stop') call,
  ];

  test('first_progress_shows_the_notice', () async {
    work.showProgress(BackgroundJob.script, writing);
    await pumpEventQueue();

    expect(platform.shown, [writing]);
  });

  test('unchanged_notice_is_not_sent_again', () async {
    work
      ..showProgress(BackgroundJob.script, writing)
      ..showProgress(BackgroundJob.script, writing);
    await pumpEventQueue();

    expect(platform.shown, [writing]);
  });

  test('notice_shows_the_job_that_started_last', () async {
    work
      ..showProgress(BackgroundJob.script, writing)
      ..showProgress(BackgroundJob.export, rendering)
      ..showProgress(BackgroundJob.script, writingMore);
    await pumpEventQueue();

    expect(platform.shown, [writing, rendering]);
  });

  test('service_keeps_running_while_another_job_runs', () async {
    work
      ..showProgress(BackgroundJob.script, writing)
      ..showProgress(BackgroundJob.export, rendering)
      ..finish(BackgroundJob.script, ready);
    await pumpEventQueue();

    expect(platform.isRunning, isTrue);
  });

  test('stop_follows_the_last_show', () async {
    work
      ..showProgress(BackgroundJob.script, writing)
      ..cancel(BackgroundJob.script);
    await pumpEventQueue();

    expect(serviceCalls(), ['show', 'stop']);
  });

  test('cancel_stops_without_a_result', () async {
    work
      ..showProgress(BackgroundJob.script, writing)
      ..cancel(BackgroundJob.script);
    await pumpEventQueue();

    expect(platform.results, isEmpty);
  });

  test('result_is_posted_only_when_the_app_is_hidden', () async {
    appIsVisible = false;

    work
      ..showProgress(BackgroundJob.script, writing)
      ..finish(BackgroundJob.script, ready);
    await pumpEventQueue();

    expect(platform.results, [(BackgroundJob.script, ready)]);
  });

  test('result_is_not_posted_while_the_app_is_on_screen', () async {
    appIsVisible = true;

    work
      ..showProgress(BackgroundJob.script, writing)
      ..finish(BackgroundJob.script, ready);
    await pumpEventQueue();

    expect(platform.results, isEmpty);
  });

  test('failed_platform_call_does_not_stop_later_calls', () async {
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);
    platform.showFailure = Exception('Service refused');

    work
      ..showProgress(BackgroundJob.script, writing)
      ..cancel(BackgroundJob.script);
    await pumpEventQueue();

    expect(serviceCalls(), ['show', 'stop']);
  });

  test('first_job_asks_for_access', () async {
    work.showProgress(BackgroundJob.script, writing);
    await pumpEventQueue();

    expect(platform.calls, contains('requestNotifications'));
  });
}
