import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:status_studio/src/features/about/domain/app_version.dart';
import 'package:status_studio/src/features/about/domain/support_message.dart';

const _system = MethodChannel('status_studio/system');

final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final package = await PackageInfo.fromPlatform();
  return AppVersion(version: package.version, build: package.buildNumber);
});

final deviceDetailsReaderProvider = Provider<DeviceDetailsReader>(
  DeviceDetailsReader.new,
);

/// Read on the phone only, fresh for every message since free memory and
/// the network change; it leaves the phone only inside a message the user
/// sends from their own app (spec FR-31, §9.2).
class DeviceDetailsReader {
  const DeviceDetailsReader(this._ref);

  final Ref _ref;

  Future<DeviceDetails> read() async {
    final appVersion = await _ref.read(appVersionProvider.future);
    final network = await _describeNetwork();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _readIphone(appVersion, network);
    }
    return _readAndroid(appVersion, network);
  }

  Future<DeviceDetails> _readAndroid(
    AppVersion appVersion,
    String network,
  ) async {
    final android = await DeviceInfoPlugin().androidInfo;
    final chip = await _system.invokeMethod<String>('processorName');
    final abi = android.supportedAbis.firstOrNull;
    return DeviceDetails(
      appVersion: appVersion,
      phone: '${_capitalised(android.manufacturer)} ${android.model}',
      system:
          'Android ${android.version.release} '
          '(SDK ${android.version.sdkInt})',
      processor: [?chip, ?abi].join(' · '),
      memory: MemorySize(
        totalMegabytes: android.physicalRamSize,
        freeMegabytes: android.availableRamSize,
      ),
      screen: _readScreen(),
      network: network,
    );
  }

  /// iOS doesn't name the chip; the model code ("iPhone15,4") pins it.
  Future<DeviceDetails> _readIphone(
    AppVersion appVersion,
    String network,
  ) async {
    final iphone = await DeviceInfoPlugin().iosInfo;
    return DeviceDetails(
      appVersion: appVersion,
      phone: iphone.modelName,
      system: 'iOS ${iphone.systemVersion}',
      processor: iphone.utsname.machine,
      memory: MemorySize(
        totalMegabytes: iphone.physicalRamSize,
        freeMegabytes: iphone.availableRamSize,
      ),
      screen: _readScreen(),
      network: network,
    );
  }
}

ScreenSize _readScreen() {
  final display = PlatformDispatcher.instance.views.first.display;
  return ScreenSize(
    widthPixels: display.size.width.round(),
    heightPixels: display.size.height.round(),
    pixelRatio: display.devicePixelRatio,
  );
}

Future<String> _describeNetwork() async {
  final connections = await Connectivity().checkConnectivity();
  return connections.map(_connectionName).join(', ');
}

String _connectionName(ConnectivityResult connection) => switch (connection) {
  ConnectivityResult.wifi => 'Wi-Fi',
  ConnectivityResult.mobile => 'Mobile data',
  ConnectivityResult.ethernet => 'Ethernet',
  ConnectivityResult.vpn => 'VPN',
  ConnectivityResult.bluetooth => 'Bluetooth',
  ConnectivityResult.satellite => 'Satellite',
  ConnectivityResult.other => 'Other',
  ConnectivityResult.none => 'None',
};

String _capitalised(String word) {
  if (word.isEmpty) return word;
  return word[0].toUpperCase() + word.substring(1);
}
