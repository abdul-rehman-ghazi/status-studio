import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/background/data/ios_background_work_platform.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';

/// The phone's side of background work: the foreground service, its
/// notifications and the permissions they need (spec FR-16). Android's is
/// [PluginBackgroundWorkPlatform]; iOS's is [IosBackgroundWorkPlatform].
abstract interface class BackgroundWorkPlatform {
  /// Starts the foreground service on the first call; later calls update
  /// its notification.
  Future<void> show(ProgressNotice notice);

  Future<void> stop();

  Future<void> postResult(BackgroundJob job, ResultNotice notice);

  /// Asks on Android 13+; true when notifications are allowed.
  Future<bool> requestNotifications();

  Future<bool> notificationsEnabled();

  /// The app's page in system Settings.
  Future<void> openAppInfo();
}

const _system = MethodChannel('status_studio/system');

/// Declared in AndroidManifest.xml, pointing at `@drawable/ic_notification`.
const _iconMetaData = 'com.hotmail.arehmananis.statusstudio.notification_icon';

/// `flutter_foreground_task` for the service and permissions,
/// `flutter_local_notifications` for results. No TaskHandler: the work
/// stays in the app's isolate; the service only keeps the process alive.
class PluginBackgroundWorkPlatform implements BackgroundWorkPlatform {
  PluginBackgroundWorkPlatform();

  final _notifications = FlutterLocalNotificationsPlugin();
  Future<void>? _notificationsReady;
  var _serviceReady = false;

  @override
  Future<void> show(ProgressNotice notice) async {
    _initServiceOnce();
    final request = await FlutterForegroundTask.isRunningService
        ? FlutterForegroundTask.updateService(
            notificationTitle: notice.title,
            notificationText: notice.body,
          )
        : FlutterForegroundTask.startService(
            serviceTypes: [ForegroundServiceTypes.dataSync],
            notificationTitle: notice.title,
            notificationText: notice.body,
            notificationIcon: const NotificationIcon(
              metaDataName: _iconMetaData,
            ),
          );
    _throwIfFailed(await request);
  }

  /// Android may have stopped it already, e.g. at the dataSync time limit.
  @override
  Future<void> stop() async {
    final request = await FlutterForegroundTask.stopService();
    if (request case ServiceRequestFailure(
      error: ServiceNotStartedException(),
    )) {
      return;
    }
    _throwIfFailed(request);
  }

  @override
  Future<void> postResult(BackgroundJob job, ResultNotice notice) async {
    await (_notificationsReady ??= _initNotifications());
    await _notifications.show(
      id: job.resultNotificationId,
      title: notice.title,
      body: notice.text,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'results',
          'Finished work',
          icon: 'ic_notification',
        ),
      ),
    );
  }

  @override
  Future<bool> requestNotifications() async =>
      await FlutterForegroundTask.requestNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<bool> notificationsEnabled() async =>
      await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<void> openAppInfo() => _system.invokeMethod<void>('openAppSettings');

  void _initServiceOnce() {
    if (_serviceReady) {
      return;
    }
    _serviceReady = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'work',
        channelName: 'Work in progress',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // Downloads keep going on Wi-Fi with the screen off.
        allowWifiLock: true,
        // A restarted service would have no work to keep alive.
        allowAutoRestart: false,
        // Not stopWithTask here: the plugin's option stops the service as
        // soon as the app leaves the screen. The manifest's
        // android:stopWithTask stops it only when the task is swiped away.
      ),
    );
  }

  Future<void> _initNotifications() => _notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
  );
}

void _throwIfFailed(ServiceRequestResult result) {
  if (result case ServiceRequestFailure(:final error)) {
    throw error;
  }
}

/// Android's foreground service, or iOS's short background task (FR-16).
final backgroundWorkPlatformProvider = Provider<BackgroundWorkPlatform>(
  (ref) => Platform.isIOS
      ? IosBackgroundWorkPlatform()
      : PluginBackgroundWorkPlatform(),
);
