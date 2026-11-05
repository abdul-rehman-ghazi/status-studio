import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/local_video_facts.dart';
import 'package:status_studio/src/features/source/data/free_storage.dart';
import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

import '../../../../helpers/fake_media_probe.dart';

const _mebibyte = 1024 * 1024;

class _FixedFreeStorage implements FreeStorage {
  _FixedFreeStorage(this.bytes);

  final int bytes;

  @override
  Future<int> freeBytes() async => bytes;
}

void main() {
  late Directory root;
  late Directory incoming;
  late SourceCache cache;
  late TranscriptStore transcripts;
  late FakeMediaProbe probe;
  late int freeBytes;

  setUp(() {
    root = Directory.systemTemp.createTempSync('local_video_importer');
    incoming = Directory('${root.path}/incoming')..createSync();
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
    ),
  );

  Uint8List bytes([int seed = 1]) =>
      Uint8List.fromList([for (var i = 0; i < 4096; i++) (i * seed) % 251]);

  File pickedFile(String name, {int seed = 1}) =>
      File('${root.path}/gallery_$name')..writeAsBytesSync(bytes(seed));

  File stagedFile(String name, {int seed = 1}) =>
      File('${incoming.path}/$name')..writeAsBytesSync(bytes(seed));

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

  test('importing_a_staged_video_moves_it', () async {
    final staged = stagedFile('shared.mp4');

    final video = await importer().importVideo(
      path: staged.path,
      displayName: 'shared.mp4',
    );

    expect(staged.existsSync(), isFalse);
    expect(cache.localVideoFile(video.videoId, 'mp4').existsSync(), isTrue);
  });

  test('importing_a_staged_duplicate_deletes_the_staged_file', () async {
    final first = pickedFile('a.mp4');
    final staged = stagedFile('shared.mp4');
    final video = await importer().importVideo(
      path: first.path,
      displayName: 'a.mp4',
    );

    await importer().importVideo(path: staged.path, displayName: 'shared.mp4');

    expect(staged.existsSync(), isFalse);
    expect(cache.keptLocalVideos(video.videoId), hasLength(1));
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

  test('importing_a_name_without_extension_keeps_it_as_mp4', () async {
    final picked = pickedFile('video');

    final video = await importer().importVideo(
      path: picked.path,
      displayName: 'video',
    );

    expect(cache.localVideoFile(video.videoId, 'mp4').existsSync(), isTrue);
  });
}
