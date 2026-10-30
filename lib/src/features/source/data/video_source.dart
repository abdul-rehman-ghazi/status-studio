import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/youtube_video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// The only door to YouTube, so a store build can swap in local files.
///
/// Failures are thrown as the typed exceptions in `source_errors.dart`.
abstract interface class VideoSource {
  Future<SourceVideo> fetchVideo(String videoId);

  /// The lowest-bitrate audio-only stream for transcription, cached and
  /// reused.
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  });

  /// Video (≤ 720p) and audio muxed into one MP4, cached and reused.
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  });
}

final videoSourceProvider = Provider<VideoSource>((ref) {
  final source = YouTubeVideoSource.open(
    cache: ref.watch(sourceCacheProvider.future),
    ffmpeg: ref.watch(ffmpegRunnerProvider),
  );
  ref.onDispose(source.close);
  return source;
});
