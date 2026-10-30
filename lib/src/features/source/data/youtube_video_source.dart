import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/mux_arguments.dart';
import 'package:status_studio/src/core/single_flight.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/source/domain/stream_choice.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

const _audioExtensions = {'mp4': 'm4a', 'webm': 'webm'};
const _downloadShare = 0.9;

/// The only class that talks to YouTube (spec §9 Distribution).
class YouTubeVideoSource implements VideoSource {
  YouTubeVideoSource(
    this._youtube, {
    required this.cache,
    required this.ffmpeg,
  });

  factory YouTubeVideoSource.open({
    required Future<SourceCache> cache,
    required FfmpegRunner ffmpeg,
  }) => YouTubeVideoSource(yt.YoutubeExplode(), cache: cache, ffmpeg: ffmpeg);

  final yt.YoutubeExplode _youtube;
  final Future<SourceCache> cache;
  final FfmpegRunner ffmpeg;

  /// Keyed by target path, so one file is never written by two downloads.
  final _downloads = SingleFlight<File>();

  void close() => _youtube.close();

  @override
  Future<SourceVideo> fetchVideo(String videoId) => _guard(() async {
    final video = await _youtube.videos.get(videoId);
    final duration = video.duration;
    if (duration == null) {
      // A live stream in progress has no length and can't be downloaded.
      throw const VideoUnavailableException('The video has no duration.');
    }
    return SourceVideo(
      videoId: videoId,
      title: video.title,
      channel: video.author,
      duration: duration,
    );
  });

  @override
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) => _guard(() => _downloadAudio(video, _AudioUse.script, onProgress));

  Future<File> _downloadAudio(
    SourceVideo video,
    _AudioUse use,
    void Function(double fraction) onProgress,
  ) async {
    final sources = await cache;
    final cached = _cachedAudio(sources, video.videoId, use);
    if (cached != null) {
      onProgress(1);
      return cached;
    }
    final streams = (await _manifest(video.videoId)).audioOnly;
    final choice = use.pick([
      for (final (index, stream) in streams.indexed)
        _audioChoice(stream, index),
    ]);
    final stream = streams[choice.index];
    final target = use.fileIn(
      sources,
      video.videoId,
      _audioExtensions[choice.container]!,
    );
    return _downloads.run(
      target.path,
      () => sources.write(
        target,
        _youtube.videos.streamsClient.get(stream),
        totalBytes: stream.size.totalBytes,
        onProgress: onProgress,
      ),
    );
  }

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) => _guard(() async {
    final sources = await cache;
    final source = sources.sourceFile(video.videoId);
    if (sources.isComplete(source)) {
      onProgress(1);
      return source;
    }
    return _downloads.run(
      source.path,
      () => _buildSource(sources, video, onProgress: onProgress),
    );
  });

  Future<File> _buildSource(
    SourceCache sources,
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    final source = sources.sourceFile(video.videoId);
    final audio = await _downloadAudio(video, _AudioUse.full, (_) {});
    final videoOnly = await _downloadVideoStream(
      sources,
      video,
      onProgress: (fraction) => onProgress(fraction * _downloadShare),
    );
    await _mux(videoOnly: videoOnly, audio: audio, target: source);
    onProgress(1);
    return source;
  }

  Future<File> _downloadVideoStream(
    SourceCache cache,
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    final target = cache.videoFile(video.videoId);
    if (cache.isComplete(target)) {
      return target;
    }
    final streams = (await _manifest(video.videoId)).videoOnly;
    final choice = pickVideoStream([
      for (final (index, stream) in streams.indexed)
        _videoChoice(stream, index),
    ]);
    final stream = streams[choice.index];
    return _downloads.run(
      target.path,
      () => cache.write(
        target,
        _youtube.videos.streamsClient.get(stream),
        totalBytes: stream.size.totalBytes,
        onProgress: onProgress,
      ),
    );
  }

  /// Muxes to a temporary name first so a half-written source never looks
  /// complete.
  Future<void> _mux({
    required File videoOnly,
    required File audio,
    required File target,
  }) async {
    final muxing = File('${target.path}.muxing.mp4');
    try {
      await ffmpeg.run(
        muxArguments(
          videoPath: videoOnly.path,
          audioPath: audio.path,
          outputPath: muxing.path,
        ),
      );
      await muxing.rename(target.path);
    } catch (_) {
      if (muxing.existsSync()) {
        await muxing.delete();
      }
      rethrow;
    }
  }

  Future<yt.StreamManifest> _manifest(String videoId) =>
      _youtube.videos.streamsClient.getManifest(videoId);
}

/// Script audio is the cheapest stream (FR-3); full audio goes with the
/// whole-video fallback source, so it keeps the best quality.
enum _AudioUse {
  script,
  full;

  StreamChoice pick(List<StreamChoice> streams) => switch (this) {
    _AudioUse.script => pickScriptAudioStream(streams),
    _AudioUse.full => pickAudioStream(streams),
  };

  File fileIn(SourceCache cache, String videoId, String extension) =>
      switch (this) {
        _AudioUse.script => cache.scriptAudioFile(videoId, extension),
        _AudioUse.full => cache.fullAudioFile(videoId, extension),
      };
}

/// The audio file already downloaded for [videoId] and [use], if any.
File? _cachedAudio(SourceCache cache, String videoId, _AudioUse use) {
  return _audioExtensions.values
      .map((extension) => use.fileIn(cache, videoId, extension))
      .where(cache.isComplete)
      .firstOrNull;
}

StreamChoice _videoChoice(yt.VideoOnlyStreamInfo stream, int index) {
  final resolution = stream.videoResolution;
  return StreamChoice(
    height: qualityHeight(width: resolution.width, height: resolution.height),
    container: stream.container.name,
    bitrate: stream.bitrate.bitsPerSecond,
    index: index,
    codec: stream.videoCodec,
  );
}

StreamChoice _audioChoice(yt.AudioOnlyStreamInfo stream, int index) {
  return StreamChoice(
    height: 0,
    container: stream.container.name,
    bitrate: stream.bitrate.bitsPerSecond,
    index: index,
    isDefaultTrack: stream.audioTrack?.audioIsDefault ?? true,
  );
}

Future<T> _guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(mapYouTubeError(error), stackTrace);
  }
}

/// Turns library and platform failures into the app's typed errors
/// (spec §8); anything else is returned unchanged to be rethrown.
Object mapYouTubeError(Object error) {
  return switch (error) {
    yt.VideoUnplayableException() => VideoUnavailableException('$error'),
    // package:http turns most dart:io network failures into ClientException.
    SocketException() ||
    HttpException() ||
    TlsException() ||
    http.ClientException() => OfflineException('$error'),
    FileSystemException(:final osError?)
        when osError.message.contains('No space') =>
      InsufficientStorageException('$error'),
    _ => error,
  };
}
