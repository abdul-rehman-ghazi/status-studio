import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_resumer.dart';
import 'package:status_studio/src/features/reel/data/fine_tune_draft_store.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import '../../../../helpers/fine_tune_drafts.dart';

final _first = DateTime.utc(2026, 11, 4, 9);
final _later = DateTime.utc(2026, 11, 4, 12);

void main() {
  late Directory root;
  late FineTuneDraftStore drafts;
  late TranscriptStore scripts;
  late FineTuneResumer resumer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fine_tune_resumer_test');
    drafts = FineTuneDraftStore(root);
    scripts = TranscriptStore(root, clock: DateTime.now);
    resumer = FineTuneResumer((
      drafts: () async => drafts,
      scripts: () async => scripts,
    ));
  });

  tearDown(() => root.delete(recursive: true));

  Future<SavedFineTune> keep({ReelDraft? reel}) async {
    final work = reel ?? pickedReelDraft();
    await scripts.saveVideo(work.video!);
    final kept = FineTuneDraft.of(work, savedAt: _first);
    await drafts.save(kept);
    return SavedFineTune(video: work.video!, draft: kept);
  }

  Future<void> saveScript(
    Transcript transcript,
    String source,
    DateTime savedAt,
  ) => scripts.save(
    fineTuneDraftFixture().script,
    SavedTranscript(transcript: transcript, source: source, savedAt: savedAt),
  );

  Transcript reworded() {
    final lines = pickedReelDraft().transcript!.lines;
    return Transcript(
      languageCode: 'ur',
      lines: [for (final line in lines) line.copyWith(text: '${line.text}!')],
    );
  }

  test('a_fitting_script_restores_the_whole_draft', () async {
    final saved = await keep();
    await saveScript(pickedReelDraft().transcript!, captionsSource, _first);

    final outcome = await resumer.resume(saved);

    expect(outcome, isA<FineTuneReady>());
    expect((outcome as FineTuneReady).draft, pickedReelDraft());
  });

  test(
    'edited_lines_reopen_from_the_edited_script_even_when_a_newer_one_exists',
    () async {
      final edited = pickedReelDraft().copyWith(linesEdited: true);
      final saved = await keep(reel: edited);
      await saveScript(edited.transcript!, editedSource, _first);
      await saveScript(reworded(), captionsSource, _later);

      final outcome = await resumer.resume(saved);

      expect(outcome, isA<FineTuneReady>());
    },
  );

  test(
    'edited_lines_with_the_edited_script_gone_compare_with_the_newest',
    () async {
      final edited = pickedReelDraft().copyWith(linesEdited: true);
      final saved = await keep(reel: edited);
      await saveScript(edited.transcript!, captionsSource, _first);

      final outcome = await resumer.resume(saved);

      expect(outcome, isA<FineTuneReady>());
    },
  );

  test('no_script_at_all_is_script_gone', () async {
    final saved = await keep();

    final outcome = await resumer.resume(saved);

    expect(outcome, isA<FineTuneScriptGone>());
  });

  test('a_rewritten_script_is_script_changed', () async {
    final saved = await keep();
    await saveScript(reworded(), captionsSource, _later);

    final outcome = await resumer.resume(saved);

    expect(outcome, isA<FineTuneScriptChanged>());
    expect((outcome as FineTuneScriptChanged).startOver.transcript, reworded());
  });

  test('script_changed_deletes_the_kept_draft', () async {
    final saved = await keep();
    await saveScript(reworded(), captionsSource, _later);

    await resumer.resume(saved);

    expect(await drafts.list(), isEmpty);
  });

  test('script_gone_deletes_the_kept_draft', () async {
    final saved = await keep();

    await resumer.resume(saved);

    expect(await drafts.list(), isEmpty);
  });

  test('a_fitting_resume_keeps_the_draft_file', () async {
    final saved = await keep();
    await saveScript(pickedReelDraft().transcript!, captionsSource, _first);

    await resumer.resume(saved);

    expect(await drafts.list(), hasLength(1));
  });
}
