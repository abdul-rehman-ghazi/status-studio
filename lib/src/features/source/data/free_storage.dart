import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How much room the phone has left for the app's files.
abstract interface class FreeStorage {
  Future<int> freeBytes();
}

/// Asked of the Kotlin side of `status_studio/video_in`, which reads the
/// app's data folder. Where that channel doesn't exist (iOS until M26) the
/// answer is unlimited: a copy that runs out of space still fails, as
/// [InsufficientStorageException] from the file system's error.
class PlatformFreeStorage implements FreeStorage {
  const PlatformFreeStorage();

  static const _channel = MethodChannel('status_studio/video_in');
  static const _unlimited = 1 << 62;

  @override
  Future<int> freeBytes() async {
    try {
      return await _channel.invokeMethod<int>('freeBytes') ?? _unlimited;
    } on MissingPluginException {
      return _unlimited;
    }
  }
}

final freeStorageProvider = Provider<FreeStorage>(
  (ref) => const PlatformFreeStorage(),
);
