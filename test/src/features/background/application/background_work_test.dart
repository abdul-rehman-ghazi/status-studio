import 'dart:async';

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

/// Each event is the percent done.
class PercentNotices implements JobNotices<int> {
  const PercentNotices();

  @override
  BackgroundJob get job => BackgroundJob.script;

  @override
  ProgressNotice get starting => progress(0);

  @override
  ProgressNotice progress(int event) =>
      ProgressNotice(title: 'Writing', text: 'Video', percent: event);

  @override
  ResultNotice get done => ready;

  @override
  ResultNotice failed(Object error) =>
      ResultNotice(title: 'Script stopped', text: '$error');
}

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

  test('stop_waits_for_the_show_before_it', () async {
    platform.showGate = Completer<void>();
    work
      ..showProgress(BackgroundJob.script, writing)
      ..cancel(BackgroundJob.script);
    await pumpEventQueue();

    platform.showGate!.complete();
    await pumpEventQueue();

    expect(platform.serviceCalls, ['show', 'stop']);
  });

  test('failed_show_is_retried_with_the_same_notice', () async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previousOnError);
    platform.showFailure = Exception('Service refused');
    work.showProgress(BackgroundJob.script, writing);
    await pumpEventQueue();

    platform.showFailure = null;
    work.showProgress(BackgroundJob.script, writing);
    await pumpEventQueue();

    expect(platform.shown, [writing]);
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

    expect(platform.serviceCalls, ['show', 'stop']);
  });

  test('first_job_asks_for_access', () async {
    work.showProgress(BackgroundJob.script, writing);
    await pumpEventQueue();

    expect(platform.calls, contains('requestNotifications'));
  });

  group('keepRunning', () {
    const notices = PercentNotices();

    test('kept_stream_passes_events_through', () async {
      final kept = work.keepRunning(Stream.fromIterable([10, 20]), notices);

      expect(await kept.toList(), [10, 20]);
    });

    test('each_event_updates_the_notice', () async {
      await work
          .keepRunning(Stream.fromIterable([10, 20]), notices)
          .drain<void>();
      await pumpEventQueue();

      expect(platform.shown.map((notice) => notice.percent), [0, 10, 20]);
    });

    test('listening_starts_the_service_before_the_first_event', () async {
      final source = StreamController<int>();
      final subscription = work
          .keepRunning(source.stream, notices)
          .listen(null);
      await pumpEventQueue();

      expect(platform.isRunning, isTrue);
      await subscription.cancel();
    });

    test('pausing_the_kept_stream_pauses_the_source', () async {
      final source = StreamController<int>();
      final subscription = work
          .keepRunning(source.stream, notices)
          .listen(null);

      subscription.pause();

      expect(source.isPaused, isTrue);
      await subscription.cancel();
    });

    test('finished_work_posts_done', () async {
      await work.keepRunning(Stream.fromIterable([10]), notices).drain<void>();
      await pumpEventQueue();

      expect(platform.results, [(BackgroundJob.script, ready)]);
    });

    test('failed_work_posts_failed', () async {
      final failing = Stream<int>.error(Exception('offline'));

      await work.keepRunning(failing, notices).drain<void>().catchError((_) {});
      await pumpEventQueue();

      expect(platform.results.single.$2.title, 'Script stopped');
    });

    test('failed_work_passes_the_error_on', () {
      final failing = Stream<int>.error(Exception('offline'));

      expect(work.keepRunning(failing, notices), emitsError(isException));
    });

    test('failed_work_stops_the_service', () async {
      final source = StreamController<int>();
      final kept = work.keepRunning(source.stream, notices);
      final subscription = kept.listen(null, onError: (Object _) {});
      source.add(10);
      await pumpEventQueue();

      source.addError(Exception('offline'));
      await pumpEventQueue();

      expect(platform.isRunning, isFalse);
      await subscription.cancel();
    });

    test('cancelled_work_cancels_the_source', () async {
      var sourceCancelled = false;
      final source = StreamController<int>(
        onCancel: () => sourceCancelled = true,
      );
      final subscription = work
          .keepRunning(source.stream, notices)
          .listen(null);
      source.add(10);
      await pumpEventQueue();

      await subscription.cancel();

      expect(sourceCancelled, isTrue);
    });

    test('cancelled_work_posts_nothing', () async {
      final source = StreamController<int>();
      final subscription = work
          .keepRunning(source.stream, notices)
          .listen(null);
      source.add(10);
      await pumpEventQueue();

      await subscription.cancel();
      await pumpEventQueue();

      expect(platform.results, isEmpty);
    });
  });
}
