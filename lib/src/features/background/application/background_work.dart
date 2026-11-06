import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/background/application/background_access.dart';
import 'package:status_studio/src/features/background/data/background_work_platform.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';

typedef BackgroundWorkServices = ({
  BackgroundWorkPlatform platform,
  BackgroundAccess access,
  bool Function() isAppVisible,
});

/// What a job's notifications say at each point of its run.
abstract interface class JobNotices<T> {
  BackgroundJob get job;

  /// Shown as soon as the work starts: its first event can take a while
  /// (a long FFmpeg run), and the user may leave before it comes.
  ProgressNotice get starting;

  ProgressNotice progress(T event);

  ResultNotice get done;

  ResultNotice failed(Object error);
}

/// Keeps the app alive while scripts and exports run, and tells the user
/// how they ended if they've left the app (spec FR-16).
class BackgroundWork {
  BackgroundWork(this._services);

  final BackgroundWorkServices _services;

  /// Running jobs in the order they started; the notification shows the
  /// last one.
  final _running = <BackgroundJob, ProgressNotice>{};

  /// What the notification shows now, so unchanged notices aren't resent.
  ProgressNotice? _shown;

  /// Platform calls run one after another, so a stop can never overtake
  /// the show before it.
  Future<void> _platformCalls = Future.value();

  /// [work] unchanged, kept running in the background from the moment
  /// it's listened to. Cancelling the result cancels [work] and ends the
  /// job quietly.
  Stream<T> keepRunning<T>(Stream<T> work, JobNotices<T> notices) =>
      _KeptRun(this, work, notices).stream;

  void showProgress(BackgroundJob job, ProgressNotice notice) {
    if (_running.isEmpty) {
      // Not queued: it waits for the user's answers, the service mustn't.
      unawaited(_reportingErrors(_services.access.askOnce));
    }
    _running[job] = notice;
    _showLatest();
  }

  /// Ends [job] and, if the user has left the app, tells them how it ended.
  void finish(BackgroundJob job, ResultNotice result) {
    cancel(job);
    if (_services.isAppVisible()) {
      return;
    }
    _queue(() => _services.platform.postResult(job, result));
  }

  /// Ends [job] without a result: the user stopped it.
  void cancel(BackgroundJob job) {
    if (_running.remove(job) == null) {
      return;
    }
    _showLatest();
  }

  void _showLatest() {
    if (_running.isEmpty) {
      _shown = null;
      _queue(_services.platform.stop);
      return;
    }
    final latest = _running.values.last;
    if (latest == _shown) {
      return;
    }
    _shown = latest;
    _queue(() => _showOrForget(latest));
  }

  /// A notice that never reached the phone is forgotten, so the next
  /// update sends it again even when it hasn't changed.
  Future<void> _showOrForget(ProgressNotice notice) async {
    try {
      await _services.platform.show(notice);
    } on Object {
      if (_shown == notice) {
        _shown = null;
      }
      rethrow;
    }
  }

  void _queue(Future<void> Function() call) {
    _platformCalls = _platformCalls.then((_) => _reportingErrors(call));
  }
}

/// One kept stream: passes [_work] through and tells [BackgroundWork]
/// where it has got to.
class _KeptRun<T> {
  _KeptRun(this._background, this._work, this._notices) {
    _kept = StreamController<T>(
      onListen: _start,
      onPause: () => _source.pause(),
      onResume: () => _source.resume(),
      onCancel: _cancel,
    );
  }

  final BackgroundWork _background;
  final Stream<T> _work;
  final JobNotices<T> _notices;
  late final StreamController<T> _kept;
  late final StreamSubscription<T> _source;

  Stream<T> get stream => _kept.stream;

  BackgroundJob get _job => _notices.job;

  void _start() {
    _background.showProgress(_job, _notices.starting);
    _source = _work.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  void _onData(T event) {
    _background.showProgress(_job, _notices.progress(event));
    _kept.add(event);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _background.finish(_job, _notices.failed(error));
    _kept.addError(error, stackTrace);
    unawaited(_kept.close());
  }

  void _onDone() {
    _background.finish(_job, _notices.done);
    unawaited(_kept.close());
  }

  /// Also runs after done or an error, when the job has already ended.
  Future<void> _cancel() {
    _background.cancel(_job);
    return _source.cancel();
  }
}

/// A refused service or notification costs the user only the background
/// guarantee; the work itself carries on.
Future<void> _reportingErrors(Future<void> Function() call) async {
  try {
    await call();
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'background work',
      ),
    );
  }
}

/// True while the app is on screen; result notifications are for when
/// it isn't.
final appIsVisibleProvider = Provider<bool Function()>(
  (ref) =>
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
);

final backgroundWorkProvider = Provider<BackgroundWork>(
  (ref) => BackgroundWork((
    platform: ref.watch(backgroundWorkPlatformProvider),
    access: ref.watch(backgroundAccessProvider),
    isAppVisible: ref.watch(appIsVisibleProvider),
  )),
);
