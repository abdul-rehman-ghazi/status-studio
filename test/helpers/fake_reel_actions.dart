import 'dart:async';

import 'package:status_studio/src/features/export/data/reel_actions.dart';

/// Records saves, shares and settings opens; refuses saves while [denied].
class FakeReelActions implements ReelActions {
  FakeReelActions({this.denied = false});

  final bool denied;
  final saved = <String>[];
  final shared = <String>[];
  var settingsOpened = 0;

  /// When set, a save waits for it before finishing.
  Completer<void>? saveGate;

  /// When set, saves fail with this.
  Exception? saveFailure;

  /// When set, shares fail with this.
  Exception? shareFailure;

  @override
  Future<void> saveToGallery(String videoPath) async {
    if (denied) {
      throw const GalleryAccessDeniedException();
    }
    await saveGate?.future;
    if (saveFailure case final failure?) {
      throw failure;
    }
    saved.add(videoPath);
  }

  @override
  Future<void> share(String videoPath) async {
    if (shareFailure case final failure?) {
      throw failure;
    }
    shared.add(videoPath);
  }

  @override
  Future<void> openAppSettings() async => settingsOpened++;
}
