import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/cache_cleanup.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// Records whether pruning ran.
class RecordingTranscriptStore extends TranscriptStore {
  RecordingTranscriptStore(super.root) : super(clock: DateTime.now);

  var pruned = 0;

  @override
  Future<int> prune() async {
    pruned++;
    return 0;
  }
}

void main() {
  late Directory root;
  final now = DateTime(2026, 11, 2, 12);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cache_cleanup_test');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  /// A video's source folder last changed [age] before [now].
  Directory sourceFolder(String videoId, Duration age) {
    final folder = Directory('${root.path}/$videoId')..createSync();
    File('${folder.path}/clip.mp4')
      ..writeAsStringSync('mp4')
      ..setLastModifiedSync(now.subtract(age));
    return folder;
  }

  test('deletes_folders_older_than_seven_days', () async {
    final old = sourceFolder('old', const Duration(days: 8));

    final deleted = await deleteStaleSources(root, now: now);

    expect((deleted, old.existsSync()), (1, false));
  });

  test('keeps_recent_folders', () async {
    final recent = sourceFolder('recent', const Duration(days: 2));

    await deleteStaleSources(root, now: now);

    expect(recent.existsSync(), isTrue);
  });

  test('missing_root_deletes_nothing', () async {
    await root.delete(recursive: true);

    expect(await deleteStaleSources(root, now: now), 0);
  });

  test('startup_cleanup_prunes_saved_scripts', () async {
    final store = RecordingTranscriptStore(Directory('${root.path}/scripts'));

    await cleanUpOnStart(
      sources: Future.value(root),
      scripts: Future.value(store),
      now: now,
    );

    expect(store.pruned, 1);
  });
}
