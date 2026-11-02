import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/mux_arguments.dart';
import 'package:status_studio/src/core/single_flight.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/data/yt_dlp_info.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/segment_index.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/source/domain/stream_choice.dart';
import 'package:status_studio/src/features/transcript/domain/caption_track_choice.dart';
import 'package:status_studio/src/features/transcript/domain/json3_captions.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

const _audioExtensions = {'mp4': 'm4a', 'webm': 'webm'};
const _downloadShare = 0.9;

/// yt-dlp's default chunk size for YouTube: larger single requests get
/// throttled.
const _rangeBytes = 10 * 1000 * 1000;

/// Stream URLs last hours; a video read this recently is reused instead of
/// running yt-dlp (about 8 s on a mid-range phone) again.
const _infoLifetime = Duration(minutes: 30);

/// Everything the source uses, in one value so it stays within three
/// parameters.
class YouTubeVideoSourceServices {
  const YouTubeVideoSourceServices({
    required this.ytDlp,
    required this.downloader,
    required this.captionClient,
    required this.cache,
    required this.ffmpeg,
  });

  final YtDlp ytDlp;
  final RangedDownloader downloader;
  final HttpClient captionClient;
  final Future<SourceCache> cache;
  final FfmpegRunner ffmpeg;
}

/// The only class that talks to YouTube (spec §9 Distribution): yt-dlp
/// reads the video, and the app downloads its streams in byte ranges.
class YouTubeVideoSource implements VideoSource {
  YouTubeVideoSource(this.services);

  final YouTubeVideoSourceServices services;

  /// Keyed by target path, so one file is never written by two downloads.
  final _downloads = SingleFlight<File>();
  final _infos = <String, ({DateTime readAt, Future<YtDlpInfo> info})>{};

  @override
  Future<SourceVideo> fetchVideo(String videoId) async =>
      (await _info(videoId)).video;

  @override
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(WorkAmount amount) onProgress,
  }) => _downloadAudio(video, _AudioUse.script, onProgress);

  Future<File> _downloadAudio(
    SourceVideo video,
    _AudioUse use,
    void Function(WorkAmount amount) onProgress,
  ) async {
    final sources = await services.cache;
    final cached = _cachedAudio(sources, video.videoId, use);
    if (cached != null) {
      final size = cached.lengthSync();
      onProgress(WorkAmount(done: size, total: size, unit: WorkUnit.bytes));
      return cached;
    }
    final formats = (await _info(video.videoId)).audioFormats;
    final format = formats[use.pick(_choicesOf(formats)).index];
    final target = use.fileIn(
      sources,
      video.videoId,
      _audioExtensions[format.choice.container] ?? format.choice.container,
    );
    return _downloads.run(
      target.path,
      () => _downloadWhole(
        format,
        target,
        (fraction) => onProgress(
          WorkAmount(
            done: (fraction * format.totalBytes).round(),
            total: format.totalBytes,
            unit: WorkUnit.bytes,
          ),
        ),
      ),
    );
  }

  @override
  Future<Transcript> fetchCaptions(
    SourceVideo video,
    ScriptLanguage language,
  ) async {
    final tracks = (await _info(video.videoId)).captionTracks;
    final choice = pickCaptionTrack([
      for (final track in tracks) track.choice,
    ], language);
    final cues = captionsFromJson3(await _json(tracks[choice.index].json3Url));
    final lines = linesFromCaptions(cues);
    if (lines.isEmpty) {
      throw const NoCaptionTrackException();
    }
    return Transcript(
      languageCode: baseLanguageCode(choice.languageCode),
      lines: lines,
    );
  }

  @override
  Future<StreamUrls> streamUrls(SourceVideo video) async =>
      _streamUrlsOf(await _info(video.videoId));

  @override
  Future<StreamUrls> freshStreamUrls(SourceVideo video) {
    _infos.remove(video.videoId);
    return streamUrls(video);
  }

  StreamUrls _streamUrlsOf(YtDlpInfo info) {
    final videoChoice = pickVideoStream(_choicesOf(info.videoFormats));
    final audioChoice = pickAudioStream(_choicesOf(info.audioFormats));
    return StreamUrls(
      video: info.videoFormats[videoChoice.index].url,
      audio: info.audioFormats[audioChoice.index].url,
      videoIsMp4: videoChoice.isPreferredContainer,
      audioIsMp4: audioChoice.isPreferredContainer,
    );
  }

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    final sources = await services.cache;
    final source = sources.sourceFile(video.videoId);
    if (sources.isComplete(source)) {
      onProgress(1);
      return source;
    }
    return _downloads.run(
      source.path,
      () => _buildSource(sources, video, onProgress: onProgress),
    );
  }

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
    final formats = (await _info(video.videoId)).videoFormats;
    final format = formats[pickVideoStream(_choicesOf(formats)).index];
    return _downloads.run(
      target.path,
      () => _downloadWhole(format, target, onProgress),
    );
  }

  /// The whole stream in [_rangeBytes] pieces, written as `.part` and
  /// renamed once complete.
  Future<File> _downloadWhole(
    YtDlpFormat format,
    File target,
    void Function(double fraction) onProgress,
  ) => guardIo(
    () => services.downloader.downloadRanges(
      RangedDownload(
        url: format.url,
        ranges: _rangesOf(format.totalBytes),
        target: target,
      ),
      onProgress: onProgress,
    ),
  );

  /// Muxes to a temporary name first so a half-written source never looks
  /// complete.
  Future<void> _mux({
    required File videoOnly,
    required File audio,
    required File target,
  }) async {
    final muxing = File('${target.path}.muxing.mp4');
    try {
      await services.ffmpeg.run(
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

  /// The video as yt-dlp reads it, reused while its URLs are fresh. A
  /// failed read is forgotten so the next attempt runs yt-dlp again.
  Future<YtDlpInfo> _info(String videoId) {
    final known = _infos[videoId];
    if (known != null &&
        DateTime.now().difference(known.readAt) < _infoLifetime) {
      return known.info;
    }
    final info = _read(videoId);
    _infos[videoId] = (readAt: DateTime.now(), info: info);
    info.ignore();
    return info.catchError((Object error, StackTrace stackTrace) {
      _infos.remove(videoId);
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  /// Without JavaScript first, which is about twice as fast; with QuickJS
  /// only when YouTube gave no streams that way (spec §10 Q4).
  Future<YtDlpInfo> _read(String videoId) async {
    final quick = YtDlpInfo.fromJson(
      await services.ytDlp.quickVideoInfo(videoId),
    );
    if (quick.videoFormats.isNotEmpty && quick.audioFormats.isNotEmpty) {
      return quick;
    }
    return YtDlpInfo.fromJson(await services.ytDlp.videoInfo(videoId));
  }

  Future<Map<String, Object?>> _json(Uri url) => guardIo(() async {
    final request = await services.captionClient.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw const NoCaptionTrackException();
    }
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, Object?>;
  });
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

List<StreamChoice> _choicesOf(List<YtDlpFormat> formats) => [
  for (final format in formats) format.choice,
];

List<ByteRange> _rangesOf(int totalBytes) => [
  for (var first = 0; first < totalBytes; first += _rangeBytes)
    ByteRange(first, math.min(first + _rangeBytes, totalBytes) - 1),
];
