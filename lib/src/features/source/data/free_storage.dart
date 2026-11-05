import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// How much room the phone has left for the app's files.
abstract interface class FreeStorage {
  /// Throws [StorageUnknownException] when the phone can't say.
  Future<int> freeBytes();
}

/// Asked of the Kotlin side of `status_studio/video_in`, which reads the
/// app's data folder. Where that channel doesn't exist (iOS until M26) or
/// can't tell, the answer is unknown: a copy that runs out of space still
/// fails, as [InsufficientStorageException] from the file system's error.
class PlatformFreeStorage implements FreeStorage {
  const PlatformFreeStorage();

  static const _channel = MethodChannel('status_studio/video_in');

  @override
  Future<int> freeBytes() async {
    try {
      final freeBytes = await _channel.invokeMethod<int>('freeBytes');
      if (freeBytes == null || freeBytes <= 0) {
        throw const StorageUnknownException('No free space was reported.');
      }
      return freeBytes;
    } on MissingPluginException {
      throw const StorageUnknownException('No free space channel.');
    } on PlatformException catch (error) {
      throw StorageUnknownException('${error.code}: ${error.message}');
    }
  }
}

final freeStorageProvider = Provider<FreeStorage>(
  (ref) => const PlatformFreeStorage(),
);
