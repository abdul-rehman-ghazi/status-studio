import 'dart:io';

import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// Answers instantly with a sample video and placeholder files.
class FakeVideoSource implements VideoSource {
  const FakeVideoSource();

  @override
  Future<SourceVideo> fetchVideo(String videoId) async {
    return SourceVideo(
      videoId: videoId,
      title: 'Sample video',
      channel: 'Sample channel',
      duration: const Duration(minutes: 6, seconds: 48),
    );
  }

  @override
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    onProgress(1);
    return File('${video.videoId}-audio.m4a');
  }

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    onProgress(1);
    return File('${video.videoId}-source.mp4');
  }
}
