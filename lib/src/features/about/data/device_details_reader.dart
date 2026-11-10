import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:status_studio/src/features/about/domain/app_version.dart';
import 'package:status_studio/src/features/about/domain/support_message.dart';

final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final package = await PackageInfo.fromPlatform();
  return AppVersion(version: package.version, build: package.buildNumber);
});

/// Read on the phone only; it leaves the phone only inside a message the
/// user sends from their own app (spec FR-31, §9.2).
final deviceDetailsProvider = FutureProvider<DeviceDetails>((ref) async {
  final appVersion = await ref.watch(appVersionProvider.future);
  final phone = await _describePhone(DeviceInfoPlugin());
  return DeviceDetails(appVersion: appVersion, phone: phone);
});

Future<String> _describePhone(DeviceInfoPlugin deviceInfo) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final iphone = await deviceInfo.iosInfo;
    return '${iphone.modelName} (iOS ${iphone.systemVersion})';
  }
  final android = await deviceInfo.androidInfo;
  return '${_capitalised(android.manufacturer)} ${android.model} '
      '(Android ${android.version.release}, SDK ${android.version.sdkInt})';
}

String _capitalised(String word) {
  if (word.isEmpty) return word;
  return word[0].toUpperCase() + word.substring(1);
}
