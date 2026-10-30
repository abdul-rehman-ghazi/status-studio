import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/youtube_video_source.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../../../helpers/fixtures.dart';

/// Fails every request, so a test passes only if nothing is downloaded.
class _OfflineClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const SocketException('Tests must not use the network.');
}

void main() {
  late Directory root;
  late SourceCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('youtube_source_test');
    cache = SourceCache(root);
  });

  tearDown(() => root.delete(recursive: true));

  test('language_rerun_reuses_cached_audio', () async {
    final cached = cache.scriptAudioFile(sampleVideo.videoId, 'm4a');
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes([1, 2, 3]);

    final reused = await HttpOverrides.runZoned(() async {
      final source = YouTubeVideoSource(
        yt.YoutubeExplode(),
        cache: Future.value(cache),
        ffmpeg: const FfmpegRunner(),
      );
      // One call per script run: the first language, then the second.
      await source.downloadScriptAudio(sampleVideo, onProgress: (_) {});
      return source.downloadScriptAudio(sampleVideo, onProgress: (_) {});
    }, createHttpClient: (_) => _OfflineClient());

    expect(reused.path, cached.path);
  });
}
