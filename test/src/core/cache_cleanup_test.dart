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
  late Directory sources;
  late Directory transcripts;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cache_cleanup_test');
    sources = Directory('${root.path}/sources')..createSync();
    transcripts = Directory('${root.path}/transcripts')..createSync();
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  /// The time [age] after the folders below were made.
  DateTime later(Duration age) => DateTime.now().add(age);

  Directory keptVideo(String videoId) {
    final folder = Directory('${sources.path}/$videoId')..createSync();
    File('${folder.path}/source.mp4').writeAsStringSync('mp4');
    return folder;
  }

  void saveScript(String videoId) {
    Directory('${transcripts.path}/$videoId').createSync();
  }

  test('orphan_source_older_than_seven_days_is_deleted', () async {
    final orphan = keptVideo('v_orphan');

    final deleted = await deleteOrphanedSources(
      sources,
      transcripts: transcripts,
      now: later(const Duration(days: 8)),
    );

    expect((deleted, orphan.existsSync()), (1, false));
  });

  test('orphan_source_younger_than_seven_days_is_kept', () async {
    final orphan = keptVideo('v_orphan');

    await deleteOrphanedSources(
      sources,
      transcripts: transcripts,
      now: later(const Duration(days: 6)),
    );

    expect(orphan.existsSync(), isTrue);
  });

  test('source_with_a_saved_script_survives_thirty_days', () async {
    final kept = keptVideo('v_scripted');
    saveScript('v_scripted');

    await deleteOrphanedSources(
      sources,
      transcripts: transcripts,
      now: later(const Duration(days: 30)),
    );

    expect(kept.existsSync(), isTrue);
  });

  test('moved_in_file_keeps_its_old_time_but_not_the_folders', () async {
    final orphan = keptVideo('v_moved');
    File('${orphan.path}/source.mp4')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(days: 20)));

    await deleteOrphanedSources(
      sources,
      transcripts: transcripts,
      now: later(const Duration(days: 1)),
    );

    expect(orphan.existsSync(), isTrue);
  });

  test('missing_sources_folder_deletes_nothing', () async {
    await sources.delete(recursive: true);

    final deleted = await deleteOrphanedSources(
      sources,
      transcripts: transcripts,
      now: later(const Duration(days: 30)),
    );

    expect(deleted, 0);
  });

  test('startup_cleanup_prunes_saved_scripts', () async {
    final store = RecordingTranscriptStore(transcripts);

    await cleanUpOnStart(
      sources: Future.value(sources),
      scripts: Future.value(store),
      now: DateTime.now(),
    );

    expect(store.pruned, 1);
  });

  test('startup_cleanup_deletes_old_orphan_sources', () async {
    final orphan = keptVideo('v_orphan');

    await cleanUpOnStart(
      sources: Future.value(sources),
      scripts: Future.value(RecordingTranscriptStore(transcripts)),
      now: later(const Duration(days: 8)),
    );

    expect(orphan.existsSync(), isFalse);
  });

  test('failed_source_cleanup_still_prunes_saved_scripts', () async {
    final store = RecordingTranscriptStore(transcripts);

    await cleanUpOnStart(
      sources: Future.error(const FileSystemException('No documents')),
      scripts: Future.value(store),
      now: DateTime.now(),
    ).catchError((Object _) {});

    expect(store.pruned, 1);
  });
}
