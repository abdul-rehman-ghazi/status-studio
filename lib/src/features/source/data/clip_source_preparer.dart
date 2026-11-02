import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/mux_arguments.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/source/domain/segment_index.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

const _firstHeadBytes = 64 * 1024;
const _maximumHeadBytes = 2 * 1024 * 1024;
const _videoShare = 0.70;
const _audioShare = 0.25;

/// What to prepare: [clip] of [video], cached in [cache].
class ClipPrepareRequest {
  const ClipPrepareRequest({
    required this.video,
    required this.clip,
    required this.cache,
  });

  final SourceVideo video;
  final ClipRange clip;
  final SourceCache cache;
}

/// One stream of a window, downloaded, and the video time it starts at.
typedef _WindowStream = ({File file, Duration start});

/// Downloads only the part of a video around a clip (FR-15): the byte
/// ranges of its video and audio segments, muxed into one clip file.
class ClipSourcePreparer {
  ClipSourcePreparer({
    required this.videos,
    required this.downloader,
    required this.ffmpeg,
  });

  final VideoSource videos;
  final RangedDownloader downloader;
  final FfmpegRunner ffmpeg;

  /// Failures are thrown as the typed errors in `source_errors.dart`.
  Future<ClipSource> prepare(
    ClipPrepareRequest request, {
    required void Function(double fraction) onProgress,
  }) => guardIo(() => _prepare(request, onProgress));

  Future<ClipSource> _prepare(
    ClipPrepareRequest request,
    void Function(double fraction) onProgress,
  ) async {
    final cached = request.cache
        .cachedClips(request.video.videoId)
        .where((source) => source.window.covers(request.clip))
        .firstOrNull;
    if (cached != null) {
      onProgress(1);
      return cached;
    }
    try {
      return await _downloadWindowRetryingOnce(request, onProgress);
    } on NoSegmentIndexException {
      return _downloadWholeVideo(request.video, onProgress);
    } on RangeNotSupportedException {
      return _downloadWholeVideo(request.video, onProgress);
    }
  }

  /// Stream URLs expire; a 403 gets one retry with fresh ones (FR-15).
  Future<ClipSource> _downloadWindowRetryingOnce(
    ClipPrepareRequest request,
    void Function(double fraction) onProgress,
  ) async {
    final video = request.video;
    try {
      final urls = await videos.streamUrls(video);
      return await _downloadWindow(request, urls, onProgress);
    } on ExpiredStreamUrlException {
      try {
        final urls = await videos.freshStreamUrls(video);
        return await _downloadWindow(request, urls, onProgress);
      } on ExpiredStreamUrlException {
        throw const VideoUnavailableException('Stream links keep expiring.');
      }
    }
  }

  Future<ClipSource> _downloadWindow(
    ClipPrepareRequest request,
    StreamUrls urls,
    void Function(double fraction) onProgress,
  ) async {
    if (!urls.videoIsMp4 || !urls.audioIsMp4) {
      throw const NoSegmentIndexException();
    }
    final window = clipWindowFor(request.clip, request.video.duration);
    final videoId = request.video.videoId;
    final video = await _downloadStream(
      urls.video,
      window,
      _StreamTarget(
        file: request.cache.windowStreamFile(videoId, window, 'video'),
        onProgress: (fraction) => onProgress(fraction * _videoShare),
      ),
    );
    final audio = await _downloadStream(
      urls.audio,
      window,
      _StreamTarget(
        file: request.cache.windowStreamFile(videoId, window, 'audio'),
        onProgress: (fraction) =>
            onProgress(_videoShare + fraction * _audioShare),
      ),
    );
    final offset = video.start < audio.start ? video.start : audio.start;
    final target = request.cache.clipFile(
      videoId,
      window: window,
      offset: offset,
    );
    await _mux(
      video: MuxInput(path: video.file.path, delay: video.start - offset),
      audio: MuxInput(path: audio.file.path, delay: audio.start - offset),
      target: target,
    );
    onProgress(1);
    return ClipSource(file: target, offset: offset, window: window);
  }

  Future<_WindowStream> _downloadStream(
    Uri url,
    ClipWindow window,
    _StreamTarget target,
  ) async {
    final index = await _readIndex(url);
    final segments = segmentsCovering(index, window);
    if (segments.isEmpty) {
      throw const NoSegmentIndexException();
    }
    final file = await downloader.downloadRanges(
      RangedDownload(
        url: url,
        ranges: [index.init, mergedRange(segments)],
        target: target.file,
      ),
      onProgress: target.onProgress,
    );
    return (file: file, start: segments.first.start);
  }

  /// Fetches the start of the stream, doubling the amount until the whole
  /// `sidx` box is in it; past 2 MiB the stream counts as having no index.
  Future<SegmentIndex> _readIndex(Uri url) async {
    var length = _firstHeadBytes;
    while (length <= _maximumHeadBytes) {
      final head = await downloader.fetchHead(url, length);
      try {
        return parseSegmentIndex(head);
      } on SegmentIndexNotFoundException catch (missing) {
        _requireMoreBytes(head, length);
        length = _nextHeadLength(length, missing.bytesNeeded);
      }
    }
    throw const NoSegmentIndexException();
  }

  Future<void> _mux({
    required MuxInput video,
    required MuxInput audio,
    required File target,
  }) async {
    final muxing = File('${target.path}.muxing.mp4');
    try {
      await ffmpeg.run(
        clipMuxArguments(video: video, audio: audio, outputPath: muxing.path),
      );
      await muxing.rename(target.path);
    } finally {
      await _deleteIfExists(muxing);
      await _deleteIfExists(File(video.path));
      await _deleteIfExists(File(audio.path));
    }
  }

  Future<ClipSource> _downloadWholeVideo(
    SourceVideo video,
    void Function(double fraction) onProgress,
  ) async {
    final file = await videos.prepareSourceVideo(video, onProgress: onProgress);
    return ClipSource(
      file: file,
      offset: Duration.zero,
      window: ClipWindow(start: Duration.zero, end: video.duration),
    );
  }
}

class _StreamTarget {
  const _StreamTarget({required this.file, required this.onProgress});

  final File file;
  final void Function(double fraction) onProgress;
}

/// A head shorter than asked for is the whole stream, so no `sidx` is
/// coming.
void _requireMoreBytes(Uint8List head, int asked) {
  if (head.length < asked) {
    throw const NoSegmentIndexException();
  }
}

int _nextHeadLength(int current, int bytesNeeded) {
  final doubled = current * 2;
  return doubled > bytesNeeded ? doubled : bytesNeeded;
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

final clipSourcePreparerProvider = Provider<ClipSourcePreparer>(
  (ref) => ClipSourcePreparer(
    videos: ref.watch(videoSourceProvider),
    downloader: ref.watch(rangedDownloaderProvider),
    ffmpeg: ref.watch(ffmpegRunnerProvider),
  ),
);
