import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// What the gallery picker came back with.
sealed class VideoPickResult {
  const VideoPickResult();
}

@immutable
class VideoPicked extends VideoPickResult {
  const VideoPicked({required this.path, required this.displayName});

  final String path;

  /// The file's name with its extension.
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is VideoPicked &&
      other.path == path &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(path, displayName);
}

/// The user closed the picker without choosing.
class VideoPickCancelled extends VideoPickResult {
  const VideoPickCancelled();
}

/// The system gallery picker (spec FR-1). It needs no permission.
abstract interface class VideoPicker {
  Future<VideoPickResult> pickVideo();
}

/// The Android Photo Picker and iOS PHPicker, through `image_picker`.
class GalleryVideoPicker implements VideoPicker {
  const GalleryVideoPicker();

  @override
  Future<VideoPickResult> pickVideo() async {
    final chosen = await ImagePicker().pickVideo(source: ImageSource.gallery);
    return videoPickResultOf(chosen);
  }
}

/// `image_picker` answers null when the user closes the picker.
VideoPickResult videoPickResultOf(XFile? chosen) {
  if (chosen == null) {
    return const VideoPickCancelled();
  }
  return VideoPicked(path: chosen.path, displayName: chosen.name);
}

final videoPickerProvider = Provider<VideoPicker>(
  (ref) => const GalleryVideoPicker(),
);
