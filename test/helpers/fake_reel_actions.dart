import 'package:status_studio/src/features/export/data/reel_actions.dart';

/// Records saves, shares and settings opens; refuses saves while [denied].
class FakeReelActions implements ReelActions {
  FakeReelActions({this.denied = false});

  final bool denied;
  final saved = <String>[];
  final shared = <String>[];
  var settingsOpened = 0;

  @override
  Future<void> saveToGallery(String videoPath) async {
    if (denied) {
      throw const GalleryAccessDeniedException();
    }
    saved.add(videoPath);
  }

  @override
  Future<void> share(String videoPath) async => shared.add(videoPath);

  @override
  Future<void> openAppSettings() async => settingsOpened++;
}
