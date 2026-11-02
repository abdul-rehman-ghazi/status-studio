import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/youtube_video_source.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
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
  /// reused. Reports the bytes received; a cached file reports itself as
  /// complete.
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(WorkAmount amount) onProgress,
  });

  /// The video's own caption track as a transcript (FR-3): manual over
  /// auto-generated, in [language] unless automatic. Throws
  /// `NoCaptionTrackException` when there is none to use.
  Future<Transcript> fetchCaptions(SourceVideo video, ScriptLanguage language);

  /// URLs for the clip's video (≤ 720p) and best audio stream. They may
  /// come from an earlier read of the video.
  Future<StreamUrls> streamUrls(SourceVideo video);

  /// As [streamUrls], but read from YouTube again: for after an
  /// [ExpiredStreamUrlException], since URLs expire and are tied to the
  /// network the phone was on.
  Future<StreamUrls> freshStreamUrls(SourceVideo video);

  /// The whole video (≤ 720p) and audio muxed into one MP4, cached and
  /// reused; the fallback when a stream can't be fetched in parts.
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  });
}

final videoSourceProvider = Provider<VideoSource>((ref) {
  final captionClient = HttpClient();
  ref.onDispose(captionClient.close);
  return YouTubeVideoSource(
    YouTubeVideoSourceServices(
      ytDlp: ref.watch(ytDlpProvider),
      downloader: ref.watch(rangedDownloaderProvider),
      captionClient: captionClient,
      cache: ref.watch(sourceCacheProvider.future),
      ffmpeg: ref.watch(ffmpegRunnerProvider),
    ),
  );
});
