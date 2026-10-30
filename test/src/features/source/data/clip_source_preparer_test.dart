import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/data/clip_source_preparer.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/source/domain/segment_index.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/mp4_fixture.dart';

/// 120 video segments of 5 s and 60 audio segments of 10 s: ten minutes.
final videoHead = buildMp4Head(
  initBytes: 800,
  timescale: 1000,
  references: List.filled(120, (1000, 5000)),
);
final audioHead = buildMp4Head(
  initBytes: 600,
  timescale: 1000,
  references: List.filled(60, (500, 10000)),
);

/// Hands out fresh stream URLs per call; counts calls and full downloads.
class UrlVideoSource extends FakeVideoSource {
  UrlVideoSource({this.mp4 = true});

  final bool mp4;
  var urlCalls = 0;
  var fullDownloads = 0;

  @override
  Future<StreamUrls> streamUrls(SourceVideo video) async {
    urlCalls++;
    return StreamUrls(
      video: Uri.parse('https://video.example/$urlCalls'),
      audio: Uri.parse('https://audio.example/$urlCalls'),
      videoIsMp4: mp4,
      audioIsMp4: mp4,
    );
  }

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    fullDownloads++;
    return super.prepareSourceVideo(video, onProgress: onProgress);
  }
}

/// Serves the fixture heads; URLs from [expiredCalls] answer 403.
class FakeRangedDownloader implements RangedDownloader {
  FakeRangedDownloader({this.expiredCalls = const {}});

  final Set<int> expiredCalls;
  final downloads = <RangedDownload>[];

  @override
  Future<Uint8List> fetchHead(Uri url, int length) async {
    _refuseExpired(url);
    final head = url.host == 'video.example' ? videoHead : audioHead;
    return Uint8List.sublistView(head, 0, length.clamp(0, head.length));
  }

  @override
  Future<File> downloadRanges(
    RangedDownload download, {
    required void Function(double fraction) onProgress,
  }) async {
    _refuseExpired(download.url);
    downloads.add(download);
    onProgress(1);
    await download.target.parent.create(recursive: true);
    return download.target.writeAsBytes([1, 2, 3]);
  }

  void _refuseExpired(Uri url) {
    if (expiredCalls.contains(int.parse(url.pathSegments.single))) {
      throw const ExpiredStreamUrlException('403');
    }
  }
}

/// Writes something at the output path instead of running FFmpeg.
class FakeFfmpegRunner implements FfmpegRunner {
  final runs = <List<String>>[];

  @override
  Future<void> run(
    List<String> arguments, {
    void Function(Duration processed)? onTime,
  }) async {
    runs.add(arguments);
    await File(arguments.last).writeAsBytes([9]);
  }

  @override
  Future<void> cancel() async {}
}

ClipRange clipAt(int startSeconds, int endSeconds) => ClipRange(
  start: Duration(seconds: startSeconds),
  end: Duration(seconds: endSeconds),
);

void main() {
  late Directory root;
  late SourceCache cache;
  late UrlVideoSource videos;
  late FakeRangedDownloader downloader;
  late ClipSourcePreparer preparer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clip_source_preparer_test');
    cache = SourceCache(root);
    videos = UrlVideoSource();
    downloader = FakeRangedDownloader();
    preparer = ClipSourcePreparer(
      videos: videos,
      downloader: downloader,
      ffmpeg: FakeFfmpegRunner(),
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<ClipSource> prepare(ClipRange clip) => preparer.prepare(
    ClipPrepareRequest(video: sampleVideo, clip: clip, cache: cache),
    onProgress: (_) {},
  );

  test('downloads_only_covering_ranges', () async {
    await prepare(clipAt(60, 100));

    final index = parseSegmentIndex(videoHead);
    expect(downloader.downloads.first.ranges, [
      index.init,
      ByteRange(index.segments[11].bytes.first, index.segments[21].bytes.last),
    ]);
  });

  test('reuses_window_that_still_covers_clip', () async {
    await prepare(clipAt(60, 100));

    await prepare(clipAt(61, 101));

    expect(downloader.downloads, hasLength(2));
  });

  test('downloads_new_window_when_clip_leaves_it', () async {
    await prepare(clipAt(60, 100));

    await prepare(clipAt(200, 230));

    expect(downloader.downloads, hasLength(4));
  });

  test('offset_is_earliest_segment_start', () async {
    final source = await prepare(clipAt(60, 100));

    expect(source.offset, const Duration(seconds: 50));
  });

  test('falls_back_to_full_download_without_index', () async {
    videos = UrlVideoSource(mp4: false);
    preparer = ClipSourcePreparer(
      videos: videos,
      downloader: downloader,
      ffmpeg: FakeFfmpegRunner(),
    );

    final source = await prepare(clipAt(60, 100));

    expect((videos.fullDownloads, source.offset), (1, Duration.zero));
  });

  test('retries_once_after_expired_url', () async {
    downloader = FakeRangedDownloader(expiredCalls: {1});
    preparer = ClipSourcePreparer(
      videos: videos,
      downloader: downloader,
      ffmpeg: FakeFfmpegRunner(),
    );

    await prepare(clipAt(60, 100));

    expect(videos.urlCalls, 2);
  });

  test('second_expired_url_surfaces_unavailable', () async {
    downloader = FakeRangedDownloader(expiredCalls: {1, 2});
    preparer = ClipSourcePreparer(
      videos: videos,
      downloader: downloader,
      ffmpeg: FakeFfmpegRunner(),
    );

    await expectLater(
      prepare(clipAt(60, 100)),
      throwsA(isA<VideoUnavailableException>()),
    );
  });

  test('cached_window_is_found_again_after_restart', () async {
    await prepare(clipAt(60, 100));
    final restarted = ClipSourcePreparer(
      videos: videos,
      downloader: downloader,
      ffmpeg: FakeFfmpegRunner(),
    );

    final source = await restarted.prepare(
      ClipPrepareRequest(
        video: sampleVideo,
        clip: clipAt(62, 98),
        cache: cache,
      ),
      onProgress: (_) {},
    );

    expect(
      (downloader.downloads.length, source.offset),
      (2, const Duration(seconds: 50)),
    );
  });
}
