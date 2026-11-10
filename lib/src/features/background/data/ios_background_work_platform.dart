import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:status_studio/src/features/background/data/background_work_platform.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';

const _system = MethodChannel('status_studio/system');

/// Background work on iOS (spec FR-16). iOS has no foreground service: the
/// app gets a few tens of seconds after the user leaves, asked for through
/// `beginBackgroundTask` in `SystemChannel.swift`, and is then suspended. A
/// script resumes from its last saved piece when the user comes back
/// (FR-14); when the time runs out the native side posts a "Work paused"
/// notification. There is no ongoing progress notification and no battery
/// setting to ask for.
class IosBackgroundWorkPlatform implements BackgroundWorkPlatform {
  IosBackgroundWorkPlatform();

  final _notifications = FlutterLocalNotificationsPlugin();
  Future<void>? _notificationsReady;

  @override
  Future<void> show(ProgressNotice notice) =>
      _system.invokeMethod<void>('beginBackgroundTask');

  @override
  Future<void> stop() => _system.invokeMethod<void>('endBackgroundTask');

  @override
  Future<void> postResult(BackgroundJob job, ResultNotice notice) async {
    await (_notificationsReady ??= _initNotifications());
    await _notifications.show(
      id: job.resultNotificationId,
      title: notice.title,
      body: notice.text,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<bool> requestNotifications() async {
    await (_notificationsReady ??= _initNotifications());
    final granted = await _iosNotifications?.requestPermissions(
      alert: true,
      sound: true,
    );
    return granted ?? false;
  }

  @override
  Future<bool> notificationsEnabled() async {
    await (_notificationsReady ??= _initNotifications());
    final options = await _iosNotifications?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  @override
  Future<void> openAppInfo() => _system.invokeMethod<void>('openAppSettings');

  IOSFlutterLocalNotificationsPlugin? get _iosNotifications => _notifications
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Permission is asked by [requestNotifications], not at start-up.
  Future<void> _initNotifications() => _notifications.initialize(
    settings: const InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      ),
    ),
  );
}
