import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_stores.dart';
import 'package:status_studio/src/features/reel/data/fine_tune_draft_store.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import '../../../../helpers/fine_tune_drafts.dart';

void main() {
  late Directory root;
  late FineTuneDraftStore drafts;
  late TranscriptStore scripts;
  late ProviderContainer container;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fine_tune_drafts_test');
    drafts = FineTuneDraftStore(root);
    scripts = TranscriptStore(root, clock: DateTime.now);
    container = ProviderContainer(
      overrides: [
        fineTuneStoresProvider.overrideWithValue((
          drafts: () async => drafts,
          scripts: () async => scripts,
        )),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });

  test('drafts_are_listed_with_their_videos', () async {
    final video = pickedReelDraft().video!;
    await scripts.saveVideo(video);
    await drafts.save(fineTuneDraftFixture());

    final listed = await container.read(fineTuneDraftsProvider.future);

    expect(listed.single.video, video);
    expect(listed.single.draft, fineTuneDraftFixture());
  });

  test('a_draft_without_a_kept_video_is_not_listed', () async {
    await drafts.save(fineTuneDraftFixture());

    final listed = await container.read(fineTuneDraftsProvider.future);

    expect(listed, isEmpty);
  });

  test('delete_removes_the_draft_and_keeps_the_script', () async {
    final video = pickedReelDraft().video!;
    await scripts.saveVideo(video);
    await scripts.save(
      fineTuneDraftFixture().script,
      SavedTranscript(
        transcript: const Transcript(languageCode: 'ur', lines: []),
        source: captionsSource,
        savedAt: DateTime.utc(2026, 11, 4),
      ),
    );
    await drafts.save(fineTuneDraftFixture());
    final listed = await container.read(fineTuneDraftsProvider.future);

    await container.read(fineTuneDraftsProvider.notifier).delete(listed.single);

    expect(await container.read(fineTuneDraftsProvider.future), isEmpty);
    expect(await scripts.list(), hasLength(1));
  });
}
