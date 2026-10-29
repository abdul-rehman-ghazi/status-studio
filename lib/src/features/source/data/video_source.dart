import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// The only door to YouTube, so a store build can swap in local files.
abstract interface class VideoSource {
  Future<SourceVideo> fetchVideo(String videoId);
}

final videoSourceProvider = Provider<VideoSource>(
  (ref) => const FakeVideoSource(),
);
