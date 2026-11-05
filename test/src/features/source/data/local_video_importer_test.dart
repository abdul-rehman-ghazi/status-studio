import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/local_video_facts.dart';
import 'package:status_studio/src/features/source/data/free_storage.dart';
import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

import '../../../../helpers/fake_media_probe.dart';

const _mebibyte = 1024 * 1024;

class _FixedFreeStorage implements FreeStorage {
  _FixedFreeStorage(this.bytes);

  /// Null means the phone can't say.
  final int? bytes;

  @override
  Future<int> freeBytes() async =>
      bytes ?? (throw const StorageUnknownException('unknown'));
}

/// A copy that ends before all its bytes arrived, as when the file changes
/// while it is read.
class _CutShortCache extends SourceCache {
  _CutShortCache(super.root);

  @override
  Future<File> write(
    File target,
    Stream<List<int>> bytes, {
    required int totalBytes,
    required void Function(double fraction) onProgress,
  }) async => throw const IncompleteDownloadException('3 of 4096 bytes.');
}

void main() {
  late Directory root;
  late Directory incoming;
  late Directory pickerCache;
  late Future<File> Function(File file, String newPath) rename;
  late SourceCache cache;
  late TranscriptStore transcripts;
  late FakeMediaProbe probe;
  late int? freeBytes;

  setUp(() {
    root = Directory.systemTemp.createTempSync('local_video_importer');
    incoming = Directory('${root.path}/incoming')..createSync();
    pickerCache = Directory('${root.path}/cache')..createSync();
    rename = (file, newPath) => file.rename(newPath);
    cache = SourceCache(Directory('${root.path}/sources'));
    transcripts = TranscriptStore(
      Directory('${root.path}/transcripts'),
      clock: DateTime.now,
    );
    probe = FakeMediaProbe();
    freeBytes = 1024 * _mebibyte;
  });

  tearDown(() => root.deleteSync(recursive: true));

  LocalVideoImporter importer() => LocalVideoImporter(
    LocalVideoImporterServices(
      cache: cache,
      transcripts: transcripts,
      probe: probe,
      storage: _FixedFreeStorage(freeBytes),
      incomingFolder: incoming,
      pickerCacheFolder: pickerCache,
      rename: (file, newPath) => rename(file, newPath),
    ),
  );

  Uint8List bytes([int seed = 1]) =>
      Uint8List.fromList([for (var i = 0; i < 4096; i++) (i * seed) % 251]);

  File pickedFile(String name, {int seed = 1}) =>
      File('${root.path}/gallery_$name')..writeAsBytesSync(bytes(seed));

  File stagedFile(String name, {int seed = 1}) =>
      File('${incoming.path}/$name')..writeAsBytesSync(bytes(seed));

  File cachedFile(String name, {int seed = 1}) =>
      File('${pickerCache.path}/$name')..writeAsBytesSync(bytes(seed));

  Future<SourceVideo> importAs(File file, String displayName) =>
      importer().importVideo(path: file.path, displayName: displayName);

  test(
    'importing_a_picked_video_keeps_it_as_source_with_its_extension',
    () async {
      final picked = pickedFile('wedding.MOV');

      final video = await importer().importVideo(
        path: picked.path,
        displayName: 'wedding.MOV',
      );

      final kept = cache.localVideoFile(video.videoId, 'mov');
      expect(kept.readAsBytesSync(), bytes());
    },
  );

  test('importing_gives_a_fingerprint_id', () async {
    final picked = pickedFile('clip.mp4');

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'clip.mp4',
    );

    expect(video.videoId, matches(RegExp(r'^v_[0-9a-f]{16}$')));
  });

  test('importing_uses_the_display_name_without_extension_as_title', () async {
    final picked = pickedFile('x');

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'Eid dua.final.mp4',
    );

    expect(video.title, 'Eid dua.final');
  });

  test('importing_uses_the_probed_duration', () async {
    final picked = pickedFile('clip.mp4');

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'clip.mp4',
    );

    expect(video.duration, const Duration(seconds: 42));
  });

  test('importing_saves_the_video_for_recent', () async {
    final picked = pickedFile('clip.mp4');

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'clip.mp4',
    );

    expect(await transcripts.loadVideo(video.videoId), video);
  });

  test('importing_a_picked_video_leaves_the_original_in_place', () async {
    final picked = pickedFile('clip.mp4');

    await importer().importVideo(path: picked.path, displayName: 'clip.mp4');

    expect(picked.existsSync(), isTrue);
  });

  test('importing_the_same_video_twice_gives_the_same_id', () async {
    final first = pickedFile('a.mp4');
    final second = pickedFile('b.mp4');

    final firstVideo = await importer().importVideo(
      path: first.path,
      displayName: 'a.mp4',
    );
    final secondVideo = await importer().importVideo(
      path: second.path,
      displayName: 'b.mp4',
    );

    expect(secondVideo.videoId, firstVideo.videoId);
  });

  test('importing_the_same_video_twice_keeps_one_copy', () async {
    final first = pickedFile('a.mp4');
    final second = pickedFile('b.mov');

    final video = await importer().importVideo(
      path: first.path,
      displayName: 'a.mp4',
    );
    await importer().importVideo(path: second.path, displayName: 'b.mov');

    expect(cache.keptLocalVideos(video.videoId), hasLength(1));
  });

  test('importing_a_staged_video_removes_it_from_staging', () async {
    final staged = stagedFile('shared.mp4');

    await importAs(staged, 'shared.mp4');

    expect(staged.existsSync(), isFalse);
  });

  test('importing_a_staged_video_keeps_it_as_source', () async {
    final staged = stagedFile('shared.mp4');

    final video = await importAs(staged, 'shared.mp4');

    expect(
      cache.localVideoFile(video.videoId, 'mp4').readAsBytesSync(),
      bytes(),
    );
  });

  test('importing_a_staged_duplicate_deletes_the_staged_file', () async {
    await importAs(pickedFile('a.mp4'), 'a.mp4');
    final staged = stagedFile('shared.mp4');

    await importAs(staged, 'shared.mp4');

    expect(staged.existsSync(), isFalse);
  });

  test('importing_a_staged_duplicate_keeps_one_copy', () async {
    final video = await importAs(pickedFile('a.mp4'), 'a.mp4');

    await importAs(stagedFile('shared.mov'), 'shared.mov');

    expect(cache.keptLocalVideos(video.videoId), hasLength(1));
  });

  test('importing_a_picker_cache_copy_removes_it_from_the_cache', () async {
    final cached = cachedFile('picked.mp4');

    await importAs(cached, 'picked.mp4');

    expect(cached.existsSync(), isFalse);
  });

  test('importing_a_picker_cache_copy_keeps_it_as_source', () async {
    final cached = cachedFile('picked.mp4');

    final video = await importAs(cached, 'picked.mp4');

    expect(
      cache.localVideoFile(video.videoId, 'mp4').readAsBytesSync(),
      bytes(),
    );
  });

  test('importing_a_rejected_picker_cache_copy_deletes_it', () async {
    probe.unreadable = const VideoUnreadableException('not a video');
    final cached = cachedFile('broken.mp4');

    await importAs(cached, 'broken.mp4').then<void>((_) {}, onError: (_) {});

    expect(cached.existsSync(), isFalse);
  });

  test('importing_a_file_outside_the_app_folders_never_deletes_it', () async {
    final picked = pickedFile('clip.mp4');

    await importAs(picked, 'clip.mp4');

    expect(picked.existsSync(), isTrue);
  });

  test(
    'a_staging_path_with_dot_dot_that_leaves_staging_is_not_deleted',
    () async {
      final picked = pickedFile('clip.mp4');
      final sneaky = File('${incoming.path}/../gallery_clip.mp4');

      await importAs(sneaky, 'clip.mp4');

      expect(picked.existsSync(), isTrue);
    },
  );

  test('a_symlink_in_staging_to_an_outside_file_leaves_that_file', () async {
    final picked = pickedFile('clip.mp4');
    final link = Link('${incoming.path}/link.mp4')..createSync(picked.path);

    await importAs(File(link.path), 'clip.mp4');

    expect(picked.existsSync(), isTrue);
  });

  test('importing_when_the_move_crosses_volumes_copies_instead', () async {
    rename = (file, newPath) => throw const FileSystemException('cross-device');
    final staged = stagedFile('shared.mp4');

    final video = await importAs(staged, 'shared.mp4');

    expect(
      cache.localVideoFile(video.videoId, 'mp4').readAsBytesSync(),
      bytes(),
    );
  });

  test(
    'importing_when_the_move_crosses_volumes_still_removes_staged',
    () async {
      rename = (file, newPath) =>
          throw const FileSystemException('cross-device');
      final staged = stagedFile('shared.mp4');

      await importAs(staged, 'shared.mp4');

      expect(staged.existsSync(), isFalse);
    },
  );

  test('importing_over_a_truncated_kept_file_replaces_it', () async {
    final first = await importAs(pickedFile('a.mp4'), 'a.mp4');
    final kept = cache.localVideoFile(first.videoId, 'mp4')
      ..writeAsBytesSync([1, 2, 3]);

    await importAs(pickedFile('b.mp4'), 'b.mp4');

    expect(kept.readAsBytesSync(), bytes());
  });

  test('importing_over_a_truncated_kept_file_of_another_extension', () async {
    final first = await importAs(pickedFile('a.mp4'), 'a.mp4');
    cache.localVideoFile(first.videoId, 'mp4').writeAsBytesSync([1, 2, 3]);

    await importAs(pickedFile('b.mov'), 'b.mov');

    expect(cache.keptLocalVideos(first.videoId).map((file) => file.path), [
      cache.localVideoFile(first.videoId, 'mov').path,
    ]);
  });

  test('importing_the_same_video_at_once_keeps_one_copy', () async {
    final first = pickedFile('a.mp4');
    final second = pickedFile('b.mov');
    final service = importer();

    final videos = await Future.wait([
      service.importVideo(path: first.path, displayName: 'a.mp4'),
      service.importVideo(path: second.path, displayName: 'b.mov'),
    ]);

    expect(cache.keptLocalVideos(videos.first.videoId), hasLength(1));
  });

  test('importing_a_video_without_audio_is_rejected', () async {
    probe.facts = const LocalVideoFacts(
      duration: Duration(seconds: 5),
      sizeBytes: 4096,
      rotationDegrees: 0,
      storedWidth: 640,
      storedHeight: 360,
      hasAudio: false,
    );
    final picked = pickedFile('silent.mp4');

    final import = importer().importVideo(
      path: picked.path,
      displayName: 'silent.mp4',
    );

    await expectLater(import, throwsA(isA<VideoUnreadableException>()));
  });

  test('importing_an_unreadable_video_is_rejected', () async {
    probe.unreadable = const VideoUnreadableException('not a video');
    final picked = pickedFile('broken.mp4');

    final import = importer().importVideo(
      path: picked.path,
      displayName: 'broken.mp4',
    );

    await expectLater(import, throwsA(isA<VideoUnreadableException>()));
  });

  test('importing_a_rejected_picked_video_keeps_nothing', () async {
    probe.unreadable = const VideoUnreadableException('not a video');
    final picked = pickedFile('broken.mp4');

    await importer()
        .importVideo(path: picked.path, displayName: 'broken.mp4')
        .then<void>((_) {}, onError: (_) {});

    expect(Directory('${root.path}/sources').existsSync(), isFalse);
  });

  test('importing_a_rejected_staged_video_deletes_it', () async {
    probe.unreadable = const VideoUnreadableException('not a video');
    final staged = stagedFile('broken.mp4');

    await importer()
        .importVideo(path: staged.path, displayName: 'broken.mp4')
        .then<void>((_) {}, onError: (_) {});

    expect(staged.existsSync(), isFalse);
  });

  test('importing_a_missing_file_is_rejected_as_unreadable', () async {
    final import = importer().importVideo(
      path: '${root.path}/gone.mp4',
      displayName: 'gone.mp4',
    );

    await expectLater(import, throwsA(isA<VideoUnreadableException>()));
  });

  test('importing_a_copy_that_leaves_under_50_mib_free_is_refused', () async {
    final picked = pickedFile('clip.mp4');
    freeBytes = picked.lengthSync() + 50 * _mebibyte - 1;

    final import = importer().importVideo(
      path: picked.path,
      displayName: 'clip.mp4',
    );

    await expectLater(import, throwsA(isA<InsufficientStorageException>()));
  });

  test('importing_a_copy_that_leaves_exactly_50_mib_free_succeeds', () async {
    final picked = pickedFile('clip.mp4');
    freeBytes = picked.lengthSync() + 50 * _mebibyte;

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'clip.mp4',
    );

    expect(cache.keptLocalVideos(video.videoId), hasLength(1));
  });

  test('importing_a_staged_video_needs_no_free_space', () async {
    final staged = stagedFile('shared.mp4');
    freeBytes = 0;

    final video = await importer().importVideo(
      path: staged.path,
      displayName: 'shared.mp4',
    );

    expect(cache.keptLocalVideos(video.videoId), hasLength(1));
  });

  test('importing_with_unknown_free_space_still_copies', () async {
    freeBytes = null;
    final picked = pickedFile('clip.mp4');

    final video = await importAs(picked, 'clip.mp4');

    expect(cache.keptLocalVideos(video.videoId), hasLength(1));
  });

  test('importing_with_an_empty_display_name_titles_it_by_file_stem', () async {
    final picked = pickedFile('holiday.mp4');

    final video = await importAs(picked, '');

    expect(video.title, 'gallery_holiday');
  });

  test('importing_a_copy_cut_short_is_unreadable_not_offline', () async {
    final picked = pickedFile('clip.mp4');
    final service = LocalVideoImporter(
      LocalVideoImporterServices(
        cache: _CutShortCache(cache.root),
        transcripts: transcripts,
        probe: probe,
        storage: _FixedFreeStorage(freeBytes),
        incomingFolder: incoming,
        pickerCacheFolder: pickerCache,
      ),
    );

    final import = service.importVideo(
      path: picked.path,
      displayName: 'clip.mp4',
    );

    await expectLater(import, throwsA(isA<VideoUnreadableException>()));
  });

  test('importing_a_name_without_extension_keeps_it_as_mp4', () async {
    final picked = pickedFile('video');

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'video',
    );

    expect(cache.localVideoFile(video.videoId, 'mp4').existsSync(), isTrue);
  });
}
