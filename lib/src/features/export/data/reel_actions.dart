import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _system = MethodChannel('status_studio/system');

/// The user refused gallery access; saving needs it granted in Settings.
class GalleryAccessDeniedException implements Exception {
  const GalleryAccessDeniedException();
}

/// What the Done screen does with a finished reel (spec FR-10).
abstract interface class ReelActions {
  /// Throws [GalleryAccessDeniedException] when access is refused, and
  /// [InsufficientStorageException] when the phone is full.
  Future<void> saveToGallery(String videoPath);

  Future<void> share(String videoPath);

  /// The app's page in system Settings, to grant a refused permission.
  Future<void> openAppSettings();
}

class DeviceReelActions implements ReelActions {
  const DeviceReelActions();

  @override
  Future<void> saveToGallery(String videoPath) async {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      throw const GalleryAccessDeniedException();
    }
    try {
      await Gal.putVideo(videoPath);
    } on GalException catch (error) {
      throw switch (error.type) {
        GalExceptionType.accessDenied => const GalleryAccessDeniedException(),
        GalExceptionType.notEnoughSpace => InsufficientStorageException(
          '$error',
        ),
        _ => error,
      };
    }
  }

  @override
  Future<void> share(String videoPath) =>
      SharePlus.instance.share(ShareParams(files: [XFile(videoPath)]));

  @override
  Future<void> openAppSettings() =>
      _system.invokeMethod<void>('openAppSettings');
}

final reelActionsProvider = Provider<ReelActions>(
  (ref) => const DeviceReelActions(),
);
