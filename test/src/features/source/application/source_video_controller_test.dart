import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/application/source_video_controller.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';

import '../../../../helpers/counting_video_source.dart';
import '../../../../helpers/fixtures.dart';

void main() {
  late CountingVideoSource videoSource;
  late ProviderContainer container;
  final videoId = sampleVideo.videoId;

  setUp(() async {
    videoSource = CountingVideoSource();
    container = ProviderContainer.test(
      overrides: [videoSourceProvider.overrideWithValue(videoSource)],
    );
    await container.read(sourceVideoProvider(videoId).future);
  });

  Future<void> prepare() => container
      .read(sourceVideoProvider(videoId).notifier)
      .prepare(sampleVideo);

  test('prepare_exposes_file_when_done', () async {
    await prepare();

    expect(
      container.read(sourceVideoProvider(videoId)).value?.path,
      '$videoId-source.mp4',
    );
  });

  test('prepare_twice_for_same_video_downloads_once', () async {
    await Future.wait([prepare(), prepare()]);
    await prepare();

    expect(videoSource.prepareCount, 1);
  });

  test('failure_surfaces_as_error_state', () async {
    videoSource.failing = true;

    await prepare();

    expect(container.read(sourceVideoProvider(videoId)).hasError, isTrue);
  });

  test('prepare_after_failure_tries_again', () async {
    videoSource.failing = true;
    await prepare();
    videoSource.failing = false;

    await prepare();

    expect(container.read(sourceVideoProvider(videoId)).value, isNotNull);
  });

  test('concurrent_retries_after_failure_download_once', () async {
    videoSource.failing = true;
    await prepare();
    videoSource.failing = false;

    await Future.wait([prepare(), prepare(), prepare()]);

    expect(videoSource.prepareCount, 2);
  });

  test('another_video_has_no_file_from_the_previous_one', () async {
    await prepare();

    final other = container.read(sourceVideoProvider('otherVideo01'));

    expect(other.value, isNull);
  });

  test('progress_is_reported', () async {
    await prepare();

    expect(container.read(sourceVideoProgressProvider(videoId)), 1.0);
  });
}
