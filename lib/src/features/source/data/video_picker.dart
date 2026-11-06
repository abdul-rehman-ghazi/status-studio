import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

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

/// What Android kept of a pick that finished while the app was gone.
sealed class LostVideoResult {
  const LostVideoResult();
}

class LostVideoFound extends LostVideoResult {
  const LostVideoFound(this.video);

  final VideoPicked video;
}

class NoLostVideo extends LostVideoResult {
  const NoLostVideo();
}

/// The system gallery picker (spec FR-1). It needs no permission.
abstract interface class VideoPicker {
  /// Throws [VideoPickFailedException] when the picker can't open or is
  /// already open.
  Future<VideoPickResult> pickVideo();

  /// Android may destroy the app while the picker is open; the chosen video
  /// is then kept for the next start. Source calls this once when it starts
  /// (spec §12 M23 task 5). Always [NoLostVideo] on iOS.
  Future<LostVideoResult> retrieveLostVideo();
}

/// The Android Photo Picker and iOS PHPicker, through `image_picker`.
class GalleryVideoPicker implements VideoPicker {
  const GalleryVideoPicker();

  @override
  Future<VideoPickResult> pickVideo() async {
    try {
      final chosen = await ImagePicker().pickVideo(source: ImageSource.gallery);
      return videoPickResultOf(chosen);
    } on PlatformException catch (error) {
      throw _pickFailure(error);
    }
  }

  @override
  Future<LostVideoResult> retrieveLostVideo() async {
    try {
      return lostVideoResultOf(await ImagePicker().retrieveLostData());
    } on PlatformException catch (error) {
      throw _pickFailure(error);
    }
  }
}

VideoPickFailedException _pickFailure(PlatformException error) =>
    VideoPickFailedException('${error.code}: ${error.message}');

/// `image_picker` answers null when the user closes the picker.
VideoPickResult videoPickResultOf(XFile? chosen) {
  if (chosen == null) {
    return const VideoPickCancelled();
  }
  return VideoPicked(path: chosen.path, displayName: chosen.name);
}

/// Only a video counts; a lost pick that had failed is reported as the
/// failure it was.
LostVideoResult lostVideoResultOf(LostDataResponse response) {
  if (response.isEmpty || response.type != RetrieveType.video) {
    return const NoLostVideo();
  }
  final failure = response.exception;
  if (failure != null) {
    throw _pickFailure(failure);
  }
  final chosen = response.files?.firstOrNull ?? response.file;
  if (chosen == null) {
    return const NoLostVideo();
  }
  return LostVideoFound(
    VideoPicked(path: chosen.path, displayName: chosen.name),
  );
}

final videoPickerProvider = Provider<VideoPicker>(
  (ref) => const GalleryVideoPicker(),
);
