import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const videoId = 'dQw4w9WgXcQ';

Stream<List<int>> chunks(int count) =>
    Stream.fromIterable(List.generate(count, (_) => [1, 2, 3, 4]));

Stream<List<int>> failingHalfway() async* {
  yield [1, 2, 3, 4];
  throw const SocketException('connection reset');
}

void main() {
  late Directory root;
  late SourceCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('source_cache_test');
    cache = SourceCache(root);
  });

  tearDown(() => root.delete(recursive: true));

  test('write_reports_progress_to_one', () async {
    final reported = <double>[];

    await cache.write(
      cache.scriptAudioFile(videoId, 'm4a'),
      chunks(4),
      totalBytes: 16,
      onProgress: reported.add,
    );

    expect(reported.last, 1.0);
  });

  test('write_renames_part_file_on_completion', () async {
    final target = cache.scriptAudioFile(videoId, 'm4a');

    await cache.write(target, chunks(2), totalBytes: 8, onProgress: (_) {});

    expect(
      (target.existsSync(), File('${target.path}.part').existsSync()),
      (true, false),
    );
  });

  test('partial_download_is_not_reused', () async {
    final target = cache.scriptAudioFile(videoId, 'm4a');

    await expectLater(
      cache.write(target, failingHalfway(), totalBytes: 8, onProgress: (_) {}),
      throwsA(isA<SocketException>()),
    );

    expect((cache.isComplete(target), target.existsSync()), (false, false));
  });

  test('complete_file_is_reused', () async {
    final target = cache.videoFile(videoId);
    await cache.write(target, chunks(1), totalBytes: 4, onProgress: (_) {});

    expect(cache.isComplete(target), isTrue);
  });

  test('files_of_one_video_share_its_folder', () {
    final folders = {
      cache.scriptAudioFile(videoId, 'm4a').parent.path,
      cache.videoFile(videoId).parent.path,
      cache.sourceFile(videoId).parent.path,
    };

    expect(folders, {'${root.path}/$videoId'});
  });

  test('short_stream_is_not_reused', () async {
    final target = cache.videoFile(videoId);

    await expectLater(
      cache.write(target, chunks(1), totalBytes: 1000, onProgress: (_) {}),
      throwsA(isA<IncompleteDownloadException>()),
    );

    expect(cache.isComplete(target), isFalse);
  });
}
