import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/reel/data/fine_tune_draft_store.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft_json.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import '../../../../helpers/fine_tune_drafts.dart';

void main() {
  late Directory root;
  late FineTuneDraftStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fine_tune_draft_store_test');
    store = FineTuneDraftStore(root);
  });

  tearDown(() => root.delete(recursive: true));

  File draftFile(String videoId, String code) =>
      File('${root.path}/$videoId/draft-$code.json');

  test('a_saved_draft_is_listed', () async {
    final draft = fineTuneDraftFixture();

    await store.save(draft);

    expect(await store.list(), [draft]);
  });

  test('saving_again_for_the_same_video_and_language_replaces_it', () async {
    final newer = fineTuneDraftFixture(savedAt: DateTime.utc(2026, 11, 5));
    await store.save(fineTuneDraftFixture());

    await store.save(newer);

    expect(await store.list(), [newer]);
  });

  test('drafts_for_two_languages_are_both_kept', () async {
    await store.save(fineTuneDraftFixture());
    await store.save(fineTuneDraftFixture(language: ScriptLanguage.auto));

    expect(await store.list(), hasLength(2));
  });

  test('drafts_are_listed_newest_first', () async {
    final older = fineTuneDraftFixture(videoId: 'old');
    final newer = fineTuneDraftFixture(
      videoId: 'new',
      savedAt: DateTime.utc(2026, 11, 5),
    );
    await store.save(older);
    await store.save(newer);

    expect(await store.list(), [newer, older]);
  });

  test('an_unreadable_draft_is_skipped', () async {
    await store.save(fineTuneDraftFixture());
    await draftFile('broken', 'ur').parent.create(recursive: true);
    await draftFile('broken', 'ur').writeAsString('{"version": 1');

    expect(await store.list(), hasLength(1));
  });

  test('a_draft_from_a_newer_version_is_skipped', () async {
    final json = fineTuneDraftToJson(fineTuneDraftFixture())..['version'] = 2;
    await draftFile('abc123', 'ur').parent.create(recursive: true);
    await draftFile('abc123', 'ur').writeAsString(jsonEncode(json));

    expect(await store.list(), isEmpty);
  });

  test('a_half_written_part_file_is_not_listed', () async {
    final json = fineTuneDraftToJson(fineTuneDraftFixture());
    await draftFile('abc123', 'ur').parent.create(recursive: true);
    await File('${draftFile('abc123', 'ur').path}.part')
        .writeAsString(jsonEncode(json));

    expect(await store.list(), isEmpty);
  });

  test('scripts_are_not_read_as_drafts', () async {
    final scripts = TranscriptStore(root, clock: DateTime.now);
    await scripts.save(
      const TranscriptKey(videoId: 'abc123', language: ScriptLanguage.urdu),
      SavedTranscript(
        transcript: const Transcript(languageCode: 'ur', lines: []),
        source: captionsSource,
        savedAt: DateTime.utc(2026, 11, 4),
      ),
    );

    expect(await store.list(), isEmpty);
  });

  test('a_draft_whose_folder_is_another_video_is_skipped', () async {
    final json = fineTuneDraftToJson(fineTuneDraftFixture());
    await draftFile('other', 'ur').parent.create(recursive: true);
    await draftFile('other', 'ur').writeAsString(jsonEncode(json));

    expect(await store.list(), isEmpty);
  });

  test('delete_removes_only_that_language', () async {
    final auto = fineTuneDraftFixture(language: ScriptLanguage.auto);
    await store.save(fineTuneDraftFixture());
    await store.save(auto);

    await store.delete(fineTuneDraftFixture().script);

    expect(await store.list(), [auto]);
  });

  test('deleting_a_draft_that_is_not_there_does_nothing', () async {
    await store.delete(fineTuneDraftFixture().script);

    expect(await store.list(), isEmpty);
  });

  test('nothing_saved_lists_nothing', () async {
    expect(
      await FineTuneDraftStore(Directory('${root.path}/none')).list(),
      isEmpty,
    );
  });

  test('a_draft_goes_when_its_video_is_pruned', () async {
    final scripts = TranscriptStore(root, clock: () => DateTime.utc(2027, 3));
    await store.save(fineTuneDraftFixture());
    await TranscriptStore(
      root,
      clock: () => DateTime.utc(2026, 11, 4),
    ).markUsed('abc123');

    await scripts.prune();

    expect(await store.list(), isEmpty);
  });
}
