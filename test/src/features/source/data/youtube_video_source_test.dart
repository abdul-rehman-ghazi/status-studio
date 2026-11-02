import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/youtube_video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

import '../../../../helpers/fake_yt_dlp.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/yt_dlp_json.dart';

const smallAudio = 4000;
const largeAudio = 9000;

/// The bytes served for [path], different per path so tests can tell
/// which stream was fetched.
List<int> bytesFor(String path, int length) =>
    List.generate(length, (i) => (i + path.length) % 256);

/// Serves media in byte ranges (206) and captions whole, as YouTube does.
Future<HttpServer> serveMedia(Map<String, int> sizes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    final response = request.response;
    if (path.startsWith('/captions/')) {
      response.write(
        jsonEncode({
          'events': [
            {
              'tStartMs': 1000,
              'dDurationMs': 2000,
              'segs': [
                {'utf8': 'from json3'},
              ],
            },
          ],
        }),
      );
      await response.close();
      return;
    }
    final body = bytesFor(path, sizes[path] ?? 0);
    final range = RegExp(r'bytes=(\d+)-(\d+)')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    final first = int.parse(range!.group(1)!);
    final last = int.parse(range.group(2)!).clamp(0, body.length - 1);
    response
      ..statusCode = HttpStatus.partialContent
      ..add(body.sublist(first, last + 1));
    await response.close();
  });
  addTearDown(server.close);
  return server;
}

Map<String, Object?> naatJson() => videoJson(
  formats: [
    audioFormat('139', ext: 'm4a', abr: 48.8, filesize: smallAudio),
    audioFormat('140', ext: 'm4a', abr: 129.5, filesize: largeAudio),
    videoFormat('134', height: 360),
  ],
  subtitles: {'en': captionFormats('en')},
);

void main() {
  late Directory root;
  late SourceCache cache;
  late HttpClient client;
  late FakeYtDlp ytDlp;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('youtube_source_test');
    cache = SourceCache(root);
    client = HttpClient();
    ytDlp = FakeYtDlp(quick: naatJson());
  });

  tearDown(() async {
    client.close(force: true);
    await root.delete(recursive: true);
  });

  YouTubeVideoSource source() => YouTubeVideoSource(
    YouTubeVideoSourceServices(
      ytDlp: ytDlp,
      downloader: RangedDownloader(client),
      captionClient: client,
      cache: Future.value(cache),
      ffmpeg: const FfmpegRunner(),
    ),
  );

  Future<void> serveNaat() async {
    final server = await serveMedia({
      '/audio/139': smallAudio,
      '/audio/140': largeAudio,
    });
    mediaBase = 'http://127.0.0.1:${server.port}';
    ytDlp.quick = naatJson();
    addTearDown(() => mediaBase = 'https://media.example');
  }

  test('fetch_video_reads_info', () async {
    final video = await source().fetchVideo('s6kE_uP3xH4');

    expect([video.title, video.channel], ['Main Madine Chala', 'Heera Gold']);
  });

  test('video_is_read_once_for_every_step', () async {
    final videos = source();

    final video = await videos.fetchVideo('s6kE_uP3xH4');
    await videos.streamUrls(video);
    await videos.streamUrls(video);

    expect(ytDlp.quickRuns, 1);
  });

  test('quick_run_without_streams_falls_back_to_solving_challenges', () async {
    ytDlp
      ..quick = videoJson(formats: const [])
      ..full = naatJson();

    final urls = await source().streamUrls(sampleVideo);

    expect([urls.audio.path, ytDlp.fullRuns], ['/audio/140', 1]);
  });

  test('fresh_stream_urls_read_the_video_again', () async {
    final videos = source();
    await videos.streamUrls(sampleVideo);

    await videos.freshStreamUrls(sampleVideo);

    expect(ytDlp.quickRuns, 2);
  });

  test('script_audio_downloads_the_lowest_bitrate_stream', () async {
    await serveNaat();

    final audio = await source().downloadScriptAudio(
      sampleVideo,
      onProgress: (_) {},
    );

    expect(await audio.readAsBytes(), bytesFor('/audio/139', smallAudio));
  });

  test('script_audio_reports_bytes_of_the_stream', () async {
    await serveNaat();
    final reported = <int>[];

    await source().downloadScriptAudio(
      sampleVideo,
      onProgress: (amount) => reported.add(amount.done),
    );

    expect([reported.first, reported.last], [0, smallAudio]);
  });

  test('language_rerun_reuses_cached_audio', () async {
    final cached = cache.scriptAudioFile(sampleVideo.videoId, 'm4a');
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes([1, 2, 3]);
    ytDlp.quick = null;

    final reused = await source().downloadScriptAudio(
      sampleVideo,
      onProgress: (_) {},
    );

    expect(reused.path, cached.path);
  });

  test('captions_come_from_the_json3_track', () async {
    await serveNaat();

    final transcript = await source().fetchCaptions(
      sampleVideo,
      ScriptLanguage.english,
    );

    expect(transcript.lines.single.text, 'from json3');
  });

  test('quick_run_failure_falls_back_to_solving_challenges', () async {
    ytDlp
      ..quick = null
      ..failure = const YouTubeChangedException('no player response')
      ..full = naatJson();

    final video = await source().fetchVideo('s6kE_uP3xH4');

    expect(video.title, 'Main Madine Chala');
  });

  test('extraction_failure_retries_after_update', () async {
    ytDlp
      ..quick = null
      ..failure = const YouTubeChangedException('no player response')
      ..fullAfterUpdate = naatJson();

    final video = await source().fetchVideo('s6kE_uP3xH4');

    expect([video.title, ytDlp.updates], ['Main Madine Chala', 1]);
  });

  test('extraction_failure_updates_once_then_reports', () async {
    ytDlp
      ..quick = null
      ..failure = const YouTubeChangedException('no player response');

    await expectLater(
      source().fetchVideo('s6kE_uP3xH4'),
      throwsA(isA<YouTubeChangedException>()),
    );
    expect(ytDlp.updates, 1);
  });

  test('unreadable_video_keeps_its_error', () async {
    ytDlp
      ..quick = null
      ..failure = const VideoUnavailableException('Private video');

    await expectLater(
      source().fetchVideo('s6kE_uP3xH4'),
      throwsA(isA<VideoUnavailableException>()),
    );
  });
}
