import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/background/data/background_work_platform.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

import '../../../../helpers/fake_background_work_platform.dart';
import '../../../../helpers/fixtures.dart';

final savedAt = DateTime.utc(2026, 11, 2, 12);

final key = TranscriptKey(
  videoId: sampleVideo.videoId,
  language: ScriptLanguage.auto,
);

/// Sends whatever the test adds to [events].
class ControlledPipeline implements ScriptPipeline {
  final events = StreamController<ScriptProgress>();

  @override
  Stream<ScriptProgress> run(SourceVideo video, ScriptLanguage language) =>
      events.stream;

  @override
  Stream<ScriptProgress> writeAgain(
    SourceVideo video,
    ScriptLanguage language,
  ) => events.stream;

  @override
  Stream<ScriptProgress> continueOnDevice(
    SourceVideo video,
    ScriptLanguage language,
  ) => events.stream;
}

void main() {
  late Directory root;
  late TranscriptStore store;
  late ControlledPipeline pipeline;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    root = await Directory.systemTemp.createTemp('saved_scripts_test');
    store = TranscriptStore(root, clock: () => savedAt);
    pipeline = ControlledPipeline();
    container = ProviderContainer.test(
      overrides: [
        transcriptStoreProvider.overrideWith((ref) async => store),
        scriptPipelineProvider.overrideWithValue(pipeline),
        backgroundWorkPlatformProvider.overrideWithValue(
          FakeBackgroundWorkPlatform(),
        ),
        appIsVisibleProvider.overrideWithValue(() => true),
      ],
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> saveScript() async {
    await store.saveVideo(sampleVideo);
    await store.save(
      key,
      SavedTranscript(
        transcript: fixture,
        source: 'captions',
        savedAt: savedAt,
      ),
    );
  }

  Future<List<String>> listedVideoIds() async => [
    for (final script in await container.read(savedScriptsProvider.future))
      script.video.videoId,
  ];

  test('lists_saved_scripts', () async {
    await saveScript();

    expect(await listedVideoIds(), [sampleVideo.videoId]);
  });

  test('finished_script_joins_the_list', () async {
    container.listen(savedScriptsProvider, (_, _) {});
    expect(await listedVideoIds(), isEmpty);
    container
        .read(scriptProgressProvider.notifier)
        .start(sampleVideo, ScriptLanguage.auto);
    await saveScript();

    pipeline.events.add(
      ScriptProgress(stage: ScriptStage.done, fraction: 1, transcript: fixture),
    );
    await pumpEventQueue();

    expect(await listedVideoIds(), [sampleVideo.videoId]);
  });

  test('delete_removes_script_from_the_list', () async {
    await saveScript();
    final script = (await container.read(savedScriptsProvider.future)).single;

    await container.read(savedScriptsProvider.notifier).delete(script);

    expect(await listedVideoIds(), isEmpty);
  });
}
