import 'package:status_studio/src/features/background/data/background_work_platform.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';

/// Records every call in order; permissions start refused.
class FakeBackgroundWorkPlatform implements BackgroundWorkPlatform {
  final calls = <String>[];
  final shown = <ProgressNotice>[];
  final results = <(BackgroundJob, ResultNotice)>[];

  var notificationsAllowed = false;
  var unrestricted = false;

  /// What [requestNotifications] answers, as if the user chose it.
  var grantsNotifications = false;

  /// Makes [show] throw, as when Android refuses to start the service.
  Object? showFailure;

  bool get isRunning => calls.lastIndexOf('show') > calls.lastIndexOf('stop');

  @override
  Future<void> show(ProgressNotice notice) async {
    calls.add('show');
    if (showFailure case final failure?) {
      throw failure;
    }
    shown.add(notice);
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> postResult(BackgroundJob job, ResultNotice notice) async {
    calls.add('postResult');
    results.add((job, notice));
  }

  @override
  Future<bool> requestNotifications() async {
    calls.add('requestNotifications');
    notificationsAllowed = grantsNotifications;
    return notificationsAllowed;
  }

  @override
  Future<bool> notificationsEnabled() async => notificationsAllowed;

  @override
  Future<bool> runsUnrestricted() async => unrestricted;

  @override
  Future<void> askToRunUnrestricted() async =>
      calls.add('askToRunUnrestricted');

  @override
  Future<void> openAppInfo() async => calls.add('openAppInfo');
}
