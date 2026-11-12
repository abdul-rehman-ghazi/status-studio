import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_fingerprint.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// The script pipeline's ID for a linked video's audio. It keeps the `v_`
/// prefix, or the start-up cleanup would delete its folder (spec FR-36).
String scriptVideoIdFor(LinkedVideo video) =>
    '${videoIdPrefix}yt_${video.videoId}';

/// Downloads a linked video's audio for Groq when it has no captions (spec
/// FR-36), as `sources/v_yt_<id>/source.m4a`, so the script pipeline writes,
/// resumes and saves it like any video.
class LinkedAudioDownloader {
  const LinkedAudioDownloader({required this.ytDlp, required this.sources});

  final YtDlp ytDlp;
  final Future<SourceCache> sources;

  /// A finished earlier download is reused without asking YouTube again.
  Future<SourceVideo> download(
    LinkedVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    final audio = (await sources).localVideoFile(
      scriptVideoIdFor(video),
      'm4a',
    );
    if (!await audio.exists()) {
      await audio.parent.create(recursive: true);
      await ytDlp.downloadAudio(
        videoId: video.videoId,
        outputPath: audio.path,
        onProgress: onProgress,
      );
    }
    return SourceVideo(
      videoId: scriptVideoIdFor(video),
      title: video.title,
      duration: video.duration,
    );
  }

  Future<void> cancel(LinkedVideo video) async {
    final audio = (await sources).localVideoFile(
      scriptVideoIdFor(video),
      'm4a',
    );
    await ytDlp.cancelDownload(audio.path);
  }
}

final linkedAudioDownloaderProvider = Provider<LinkedAudioDownloader>(
  (ref) => LinkedAudioDownloader(
    ytDlp: ref.watch(ytDlpProvider),
    sources: ref.watch(sourceCacheProvider.future),
  ),
);
