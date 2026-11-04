import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/data/fine_tune_draft_store.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';

import '../../../../helpers/fine_tune_drafts.dart';

void main() {
  late Directory root;
  late FineTuneDraftStore drafts;
  late FineTuneDraftSaver saver;
  late int changes;
  late int opened;
  late int clockTicks;
  late bool failNextOpen;
  late Object openFailure;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fine_tune_saver_test');
    drafts = FineTuneDraftStore(root);
    changes = 0;
    opened = 0;
    clockTicks = 0;
    failNextOpen = false;
    openFailure = const FileSystemException('disk full');
    final scripts = TranscriptStore(root, clock: DateTime.now);
    saver = FineTuneDraftSaver(
      stores: (
        drafts: () async {
          opened++;
          if (failNextOpen) {
            failNextOpen = false;
            throw openFailure;
          }
          return drafts;
        },
        scripts: () async => scripts,
      ),
      onChanged: () => changes++,
      clock: () =>
          DateTime.utc(2026, 11, 4).add(Duration(minutes: clockTicks++)),
    );
  });

  tearDown(() => root.delete(recursive: true));

  ReelDraft reworded(ReelDraft draft) =>
      draft.copyWith(caption: draft.caption.copyWith(text: 'changed'));

  test('save_writes_the_draft_for_its_video_and_language', () async {
    await saver.save(pickedReelDraft());

    final kept = (await drafts.list()).single;
    expect(kept.script.videoId, 'abc123');
    expect(kept.script.language, ScriptLanguage.urdu);
  });

  test('a_draft_without_a_clip_is_not_saved', () async {
    await saver.save(pickedReelDraft().withSelection(const StartSelected(1)));

    expect(await drafts.list(), isEmpty);
  });

  test('saving_the_same_draft_twice_writes_once', () async {
    await saver.save(pickedReelDraft());
    final firstSavedAt = (await drafts.list()).single.savedAt;

    await saver.save(pickedReelDraft());

    expect((await drafts.list()).single.savedAt, firstSavedAt);
  });

  test('saving_a_change_writes_again', () async {
    await saver.save(pickedReelDraft());

    await saver.save(reworded(pickedReelDraft()));

    expect((await drafts.list()).single.caption.text, 'changed');
  });

  test('saving_marks_the_video_used', () async {
    await saver.save(pickedReelDraft());

    expect(File('${root.path}/abc123/last_used').existsSync(), isTrue);
  });

  test('saving_tells_the_list_to_refresh', () async {
    await saver.save(pickedReelDraft());

    expect(changes, 1);
  });

  test('discard_deletes_the_saved_draft', () async {
    await saver.save(pickedReelDraft());

    await saver.discard(pickedReelDraft());

    expect(await drafts.list(), isEmpty);
  });

  test('the_exported_draft_is_not_saved_again', () async {
    await saver.save(pickedReelDraft());
    await saver.discard(pickedReelDraft());

    await saver.save(pickedReelDraft());

    expect(await drafts.list(), isEmpty);
  });

  test('a_change_after_export_is_saved', () async {
    await saver.save(pickedReelDraft());
    await saver.discard(pickedReelDraft());

    await saver.save(reworded(pickedReelDraft()));

    expect(await drafts.list(), hasLength(1));
  });

  test('discard_waits_for_a_save_in_progress', () async {
    final saving = saver.save(pickedReelDraft());

    await saver.discard(pickedReelDraft());
    await saving;

    expect(await drafts.list(), isEmpty);
  });

  test('an_error_in_one_save_does_not_block_the_next', () async {
    failNextOpen = true;
    openFailure = StateError('broken');
    await saver.save(pickedReelDraft());

    await saver.save(pickedReelDraft());

    expect(await drafts.list(), hasLength(1));
  });

  test('a_draft_deleted_elsewhere_is_written_again', () async {
    await saver.save(pickedReelDraft());
    await drafts.delete((await drafts.list()).single.script);

    await saver.save(pickedReelDraft());

    expect(await drafts.list(), hasLength(1));
  });

  test('remembering_the_continued_work_stops_a_repeat_write', () async {
    await drafts.save(
      FineTuneDraft.of(pickedReelDraft(), savedAt: DateTime.utc(2026)),
    );
    await saver.rememberKept(pickedReelDraft());

    await saver.save(pickedReelDraft());

    expect((await drafts.list()).single.savedAt, DateTime.utc(2026));
  });

  test('a_failed_save_does_not_block_the_next', () async {
    failNextOpen = true;
    await saver.save(pickedReelDraft());

    await saver.save(pickedReelDraft());

    expect(await drafts.list(), hasLength(1));
    expect(opened, 2);
  });
}
