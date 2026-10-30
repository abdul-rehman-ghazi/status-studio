import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/youtube_video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Where to fetch the chosen video and audio streams from, and whether they
/// are MP4 (only MP4 has the segment index partial downloads need).
@immutable
class StreamUrls {
  const StreamUrls({
    required this.video,
    required this.audio,
    required this.videoIsMp4,
    required this.audioIsMp4,
  });

  final Uri video;
  final Uri audio;
  final bool videoIsMp4;
  final bool audioIsMp4;

  @override
  bool operator ==(Object other) =>
      other is StreamUrls &&
      other.video == video &&
      other.audio == audio &&
      other.videoIsMp4 == videoIsMp4 &&
      other.audioIsMp4 == audioIsMp4;

  @override
  int get hashCode => Object.hash(video, audio, videoIsMp4, audioIsMp4);
}

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

  /// The video's own caption track as a transcript (FR-3): manual over
  /// auto-generated, in [language] unless automatic. Throws
  /// `NoCaptionTrackException` when there is none to use.
  Future<Transcript> fetchCaptions(SourceVideo video, ScriptLanguage language);

  /// Fresh URLs for the clip's video (≤ 720p) and best audio stream. They
  /// expire, so ask again after an [ExpiredStreamUrlException].
  Future<StreamUrls> streamUrls(SourceVideo video);

  /// The whole video (≤ 720p) and audio muxed into one MP4, cached and
  /// reused; the fallback when a stream can't be fetched in parts.
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
