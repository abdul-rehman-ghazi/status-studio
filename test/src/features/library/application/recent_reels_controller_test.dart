import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/recording_ffmpeg.dart';

void main() {
  late Directory folder;
  late File video;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    folder = await Directory.systemTemp.createTemp('recent_reels_controller');
    video = File('${folder.path}/reel_1.mp4')..writeAsStringSync('mp4');
  });

  tearDown(() => folder.delete(recursive: true));

  ProviderContainer containerWith(RecordingFfmpegRunner ffmpeg) =>
      ProviderContainer.test(
        overrides: [ffmpegRunnerProvider.overrideWithValue(ffmpeg)],
      );

  test('keep_writes_thumbnail_beside_the_reel', () async {
    final ffmpeg = RecordingFfmpegRunner();
    final container = containerWith(ffmpeg);

    final reel = await container
        .read(recentReelsProvider.notifier)
        .keep(video.path, pickedDraft);

    expect(
      (ffmpeg.runs.single.last, reel.thumbnailPath),
      ('${folder.path}/reel_1.jpg', '${folder.path}/reel_1.jpg'),
    );
  });

  test('keep_adds_reel_as_newest', () async {
    final container = containerWith(RecordingFfmpegRunner());

    await container
        .read(recentReelsProvider.notifier)
        .keep(video.path, pickedDraft);

    final reels = await container.read(recentReelsProvider.future);
    expect(
      (reels.single.id, reels.single.title, reels.single.duration),
      (
        'reel_1',
        pickedDraft.caption.text.split('\n').first,
        pickedDraft.clip!.length,
      ),
    );
  });

  test('keep_survives_thumbnail_failure', () async {
    final container = containerWith(RecordingFfmpegRunner(failing: true));

    await container
        .read(recentReelsProvider.notifier)
        .keep(video.path, pickedDraft);

    expect(await container.read(recentReelsProvider.future), hasLength(1));
  });
}
