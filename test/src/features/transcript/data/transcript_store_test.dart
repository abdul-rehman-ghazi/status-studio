import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

final start = DateTime.utc(2026, 10, 30, 12);

const transcript = Transcript(
  languageCode: 'ur',
  lines: [
    TranscriptLine(
      index: 0,
      text: 'علم بڑی دولت ہے',
      start: Duration(milliseconds: 1500),
      end: Duration(milliseconds: 4200),
    ),
  ],
);

TranscriptKey keyFor(String videoId) =>
    TranscriptKey(videoId: videoId, language: ScriptLanguage.auto);

SourceVideo videoWithId(String videoId) => SourceVideo(
  videoId: videoId,
  title: 'Video $videoId',
  channel: 'Channel',
  duration: const Duration(minutes: 3),
);

void main() {
  late Directory root;
  late DateTime now;
  late TranscriptStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('transcript_store_test');
    now = start;
    store = TranscriptStore(root, clock: () => now);
  });

  tearDown(() => root.delete(recursive: true));

  SavedTranscript savedAt(DateTime time, {String source = 'captions'}) =>
      SavedTranscript(transcript: transcript, source: source, savedAt: time);

  test('save_then_load_round_trips', () async {
    await store.save(keyFor('a'), savedAt(start));

    expect(await store.load(keyFor('a')), savedAt(start));
  });

  test('load_missing_throws_no_saved_transcript', () async {
    await expectLater(
      store.load(keyFor('missing')),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  test('load_prefers_newest_source', () async {
    await store.save(keyFor('a'), savedAt(start));
    final newer = savedAt(
      start.add(const Duration(hours: 1)),
      source: 'whisper-small',
    );
    await store.save(keyFor('a'), newer);

    expect((await store.load(keyFor('a'))).source, 'whisper-small');
  });

  test('scripts_are_kept_per_requested_language', () async {
    await store.save(keyFor('a'), savedAt(start));

    await expectLater(
      store.load(
        const TranscriptKey(videoId: 'a', language: ScriptLanguage.english),
      ),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  test('partial_round_trips_and_clears', () async {
    final partial = PartialTranscript(
      completedChunks: 2,
      lines: transcript.lines,
    );
    await store.savePartial(keyFor('a'), groqSource, partial);
    final loaded = await store.loadPartial(keyFor('a'), groqSource);

    await store.clearPartial(keyFor('a'), groqSource);

    expect(loaded, partial);
    await expectLater(
      store.loadPartial(keyFor('a'), groqSource),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  test('prune_removes_entries_unused_for_ninety_days', () async {
    await store.save(keyFor('old'), savedAt(start));
    now = start.add(const Duration(days: 60));
    await store.save(keyFor('recent'), savedAt(now));
    now = start.add(const Duration(days: 91));

    await store.prune();

    await expectLater(
      store.load(keyFor('old')),
      throwsA(isA<NoSavedTranscriptException>()),
    );
    expect((await store.load(keyFor('recent'))).source, 'captions');
  });

  test('loading_counts_as_use_for_pruning', () async {
    await store.save(keyFor('a'), savedAt(start));
    now = start.add(const Duration(days: 80));
    await store.load(keyFor('a'));
    now = start.add(const Duration(days: 100));

    await store.prune();

    expect((await store.load(keyFor('a'))).source, 'captions');
  });

  test('prune_keeps_video_with_only_partial_progress', () async {
    await store.savePartial(
      keyFor('resuming'),
      groqSource,
      const PartialTranscript(completedChunks: 1, lines: []),
    );
    now = start.add(const Duration(days: 1));

    await store.prune();

    final partial = await store.loadPartial(keyFor('resuming'), groqSource);
    expect(partial.completedChunks, 1);
  });

  test('prune_keeps_two_hundred_most_recent_videos', () async {
    for (var video = 0; video < 202; video++) {
      now = start.add(Duration(minutes: video));
      await store.save(keyFor('v$video'), savedAt(now));
    }

    final removed = await store.prune();

    expect(removed, 2);
    await expectLater(
      store.load(keyFor('v0')),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  test('corrupt_file_is_treated_as_missing', () async {
    await store.save(keyFor('a'), savedAt(start));
    final saved = Directory('${root.path}/a')
        .listSync()
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('-captions.json'));
    await saved.writeAsString('{not json');

    await expectLater(
      store.load(keyFor('a')),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  group('list', () {
    Future<void> saveWithVideo(TranscriptKey key, SavedTranscript saved) async {
      await store.saveVideo(videoWithId(key.videoId));
      await store.save(key, saved);
    }

    test('list_returns_finished_script_with_its_video', () async {
      await saveWithVideo(keyFor('a'), savedAt(start));

      expect(await store.list(), [
        SavedScript(
          video: videoWithId('a'),
          language: ScriptLanguage.auto,
          saved: savedAt(start),
        ),
      ]);
    });

    test('list_leaves_out_scripts_without_video_details', () async {
      await store.save(keyFor('a'), savedAt(start));

      expect(await store.list(), isEmpty);
    });

    test('list_has_one_entry_per_language', () async {
      await saveWithVideo(keyFor('a'), savedAt(start));
      await store.save(
        const TranscriptKey(videoId: 'a', language: ScriptLanguage.english),
        savedAt(start),
      );

      final languages = [
        for (final script in await store.list()) script.language,
      ];

      expect(
        languages,
        unorderedEquals([ScriptLanguage.auto, ScriptLanguage.english]),
      );
    });

    test('list_shows_newest_source_of_a_language', () async {
      await saveWithVideo(keyFor('a'), savedAt(start));
      await store.save(
        keyFor('a'),
        savedAt(start.add(const Duration(hours: 1)), source: 'whisper-small'),
      );

      final sources = [
        for (final script in await store.list()) script.saved.source,
      ];

      expect(sources, ['whisper-small']);
    });

    test('list_is_newest_first', () async {
      await saveWithVideo(keyFor('old'), savedAt(start));
      await saveWithVideo(
        keyFor('new'),
        savedAt(start.add(const Duration(hours: 1))),
      );

      final videoIds = [
        for (final script in await store.list()) script.video.videoId,
      ];

      expect(videoIds, ['new', 'old']);
    });

    test('list_leaves_out_unfinished_scripts', () async {
      await store.saveVideo(videoWithId('a'));
      await store.savePartial(
        keyFor('a'),
        groqSource,
        PartialTranscript(completedChunks: 1, lines: transcript.lines),
      );

      expect(await store.list(), isEmpty);
    });

    test('delete_removes_the_languages_script', () async {
      await saveWithVideo(keyFor('a'), savedAt(start));
      await store.save(keyFor('a'), savedAt(start, source: 'whisper-small'));

      await store.delete(keyFor('a'));

      await expectLater(
        store.load(keyFor('a')),
        throwsA(isA<NoSavedTranscriptException>()),
      );
    });

    test('delete_keeps_other_languages', () async {
      const english = TranscriptKey(
        videoId: 'a',
        language: ScriptLanguage.english,
      );
      await saveWithVideo(keyFor('a'), savedAt(start));
      await store.save(english, savedAt(start));

      await store.delete(keyFor('a'));

      expect((await store.load(english)).source, 'captions');
    });
  });

  group('removeWhisperScripts', () {
    Future<void> touch(String videoId, String name) async {
      final file = File('${root.path}/$videoId/$name');
      await file.create(recursive: true);
      await file.writeAsString('{}');
    }

    Future<List<String>> namesIn(String videoId) async => [
      for (final entry in Directory('${root.path}/$videoId').listSync())
        entry.path.split('/').last,
    ]..sort();

    test('removes_whisper_scripts_and_progress_of_every_video', () async {
      await touch('a', 'ur-whisper-small.json');
      await touch('a', 'ur-whisper-small.partial.json');
      await touch('b', 'auto-whisper-medium.json');

      await store.removeWhisperScripts();

      expect(await namesIn('a'), isEmpty);
      expect(await namesIn('b'), isEmpty);
    });

    test('keeps_captions_groq_scripts_and_the_video_file', () async {
      await touch('a', 'ur-captions.json');
      await touch('a', 'ur-groq-whisper-large-v3-turbo.json');
      await touch('a', 'ur-groq-whisper-large-v3-turbo.partial.json');
      await touch('a', 'video.json');
      await touch('a', 'ur-whisper-base.json');

      await store.removeWhisperScripts();

      expect(await namesIn('a'), [
        'ur-captions.json',
        'ur-groq-whisper-large-v3-turbo.json',
        'ur-groq-whisper-large-v3-turbo.partial.json',
        'video.json',
      ]);
    });

    test('does_nothing_before_anything_is_saved', () async {
      final missing = Directory('${root.path}/never_made');

      await TranscriptStore(missing, clock: () => now).removeWhisperScripts();

      expect(await missing.exists(), isFalse);
    });
  });
}
