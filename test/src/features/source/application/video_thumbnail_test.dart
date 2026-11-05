import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/application/video_thumbnail.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

import '../../../../helpers/recording_ffmpeg.dart';

void main() {
  late Directory root;
  late SourceCache cache;
  late RecordingFfmpegRunner ffmpeg;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('thumbnail_test');
    cache = SourceCache(root);
    ffmpeg = RecordingFfmpegRunner();
    container = ProviderContainer(
      overrides: [
        sourceCacheProvider.overrideWith((ref) async => cache),
        ffmpegRunnerProvider.overrideWithValue(ffmpeg),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  File keepVideo(String videoId) {
    final video = cache.localVideoFile(videoId, 'mp4');
    video.parent.createSync(recursive: true);
    return video..writeAsBytesSync(const [1, 2, 3]);
  }

  test('thumbnail_is_cut_from_the_kept_video', () async {
    final video = keepVideo('v_a');

    final thumbnail = await container.read(
      videoThumbnailProvider('v_a').future,
    );

    expect(ffmpeg.runs.single, contains(video.path));
    expect(thumbnail.path, cache.thumbnailFile('v_a').path);
  });

  test('thumbnail_already_made_is_not_cut_again', () async {
    keepVideo('v_b');
    cache.thumbnailFile('v_b').writeAsBytesSync(const [9]);

    await container.read(videoThumbnailProvider('v_b').future);

    expect(ffmpeg.runs, isEmpty);
  });

  test('thumbnail_for_a_video_that_is_not_kept_throws', () async {
    final thumbnail = container.read(
      videoThumbnailProvider('v_missing').future,
    );

    await expectLater(thumbnail, throwsA(isA<VideoUnreadableException>()));
  });
}
