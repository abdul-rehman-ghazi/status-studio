import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/background/data/background_work_platform.dart';

const _askedKey = 'background.accessAsked';

typedef BackgroundAccessStatus = ({bool notifications, bool unrestricted});

/// The permissions background work needs: notifications for its results,
/// and exemption from battery optimisation so Android doesn't pause it
/// (spec FR-16).
class BackgroundAccess {
  const BackgroundAccess(this._platform, this._preferences);

  final BackgroundWorkPlatform _platform;
  final SharedPreferencesAsync _preferences;

  /// The first time any work starts; Settings offers both again later.
  Future<void> askOnce() async {
    if (await _preferences.getBool(_askedKey) ?? false) {
      return;
    }
    await _preferences.setBool(_askedKey, true);
    await _platform.requestNotifications();
    if (!await _platform.runsUnrestricted()) {
      await _platform.askToRunUnrestricted();
    }
  }

  Future<BackgroundAccessStatus> status() async => (
    notifications: await _platform.notificationsEnabled(),
    unrestricted: await _platform.runsUnrestricted(),
  );

  /// Android stops asking once the user has refused twice; then only App
  /// info can turn notifications on.
  Future<void> allowNotifications() async {
    if (await _platform.requestNotifications()) {
      return;
    }
    await _platform.openAppInfo();
  }

  Future<void> allowUnrestricted() => _platform.askToRunUnrestricted();

  Future<void> openAppInfo() => _platform.openAppInfo();
}

final backgroundAccessProvider = Provider<BackgroundAccess>(
  (ref) => BackgroundAccess(
    ref.watch(backgroundWorkPlatformProvider),
    ref.watch(preferencesProvider),
  ),
);
