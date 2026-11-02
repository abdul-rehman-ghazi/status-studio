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
    _queue(() => _services.platform.show(latest));
  }

  void _queue(Future<void> Function() call) {
    _platformCalls = _platformCalls.then((_) => _reportingErrors(call));
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
