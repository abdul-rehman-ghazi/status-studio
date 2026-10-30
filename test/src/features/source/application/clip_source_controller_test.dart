import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/data/clip_source_preparer.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';

import '../../../../helpers/fake_clip_preparer.dart';
import '../../../../helpers/fixtures.dart';

ClipRange clipAt(int startSeconds, int endSeconds) => ClipRange(
  start: Duration(seconds: startSeconds),
  end: Duration(seconds: endSeconds),
);

void main() {
  late FakeClipSourcePreparer preparer;
  late ProviderContainer container;
  final videoId = sampleVideo.videoId;

  setUp(() async {
    preparer = FakeClipSourcePreparer();
    container = ProviderContainer.test(
      overrides: [
        clipSourcePreparerProvider.overrideWithValue(preparer),
        sourceCacheProvider.overrideWith(
          (ref) async => SourceCache(Directory.systemTemp),
        ),
      ],
    );
    await container.read(clipSourceProvider(videoId).future);
  });

  Future<void> prepareFor(ClipRange clip) => container
      .read(clipSourceProvider(videoId).notifier)
      .prepareFor(sampleVideo, clip);

  test('prepare_exposes_clip_source', () async {
    await prepareFor(clipAt(60, 100));

    expect(
      container.read(clipSourceProvider(videoId)).value?.offset,
      const Duration(seconds: 55),
    );
  });

  test('nudge_inside_window_does_not_redownload', () async {
    await prepareFor(clipAt(60, 100));

    await prepareFor(clipAt(61, 101));

    expect(preparer.calls, 1);
  });

  test('clip_leaving_window_downloads_again', () async {
    await prepareFor(clipAt(60, 100));

    await prepareFor(clipAt(200, 230));

    expect(preparer.calls, 2);
  });

  test('concurrent_requests_for_one_window_download_once', () async {
    await Future.wait([
      prepareFor(clipAt(60, 100)),
      prepareFor(clipAt(60, 100)),
    ]);

    expect(preparer.calls, 1);
  });

  test('failure_surfaces_as_error_state', () async {
    preparer.failing = true;

    await prepareFor(clipAt(60, 100));

    expect(container.read(clipSourceProvider(videoId)).hasError, isTrue);
  });

  test('prepare_after_failure_tries_again', () async {
    preparer.failing = true;
    await prepareFor(clipAt(60, 100));
    preparer.failing = false;

    await prepareFor(clipAt(60, 100));

    expect(container.read(clipSourceProvider(videoId)).value, isNotNull);
  });

  test('progress_is_reported', () async {
    await prepareFor(clipAt(60, 100));

    expect(container.read(clipSourceProgressProvider(videoId)), 1.0);
  });
}
