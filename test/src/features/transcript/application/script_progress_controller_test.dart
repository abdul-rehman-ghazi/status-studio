import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/background/data/background_work_platform.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';

import '../../../../helpers/fake_background_work_platform.dart';
import '../../../../helpers/fixtures.dart';

/// Each run starts, then waits at its gate the way a pipeline waits on a
/// download or a Whisper chunk.
class GatedPipeline implements ScriptPipeline {
  final started = <ScriptLanguage>[];
  final gate = Completer<void>();

  @override
  Stream<ScriptProgress> run(
    SourceVideo video,
    ScriptLanguage language,
  ) async* {
    started.add(language);
    await gate.future;
    yield ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: fixture,
    );
  }

  @override
  Stream<ScriptProgress> writeAgain(
    SourceVideo video,
    ScriptLanguage language,
  ) => run(video, language);
}

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
}

void main() {
  late GatedPipeline pipeline;
  late FakeBackgroundWorkPlatform background;
  late ProviderContainer container;

  ProviderContainer containerWith(ScriptPipeline pipeline) =>
      ProviderContainer.test(
        overrides: [
          scriptPipelineProvider.overrideWithValue(pipeline),
          backgroundWorkPlatformProvider.overrideWithValue(background),
          appIsVisibleProvider.overrideWithValue(() => true),
        ],
      );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    background = FakeBackgroundWorkPlatform();
    pipeline = GatedPipeline();
    container = containerWith(pipeline);
  });

  ScriptProgressController controller() =>
      container.read(scriptProgressProvider.notifier);

  test('restart_waits_while_previous_run_is_busy', () async {
    controller().start(sampleVideo, ScriptLanguage.urdu);
    await pumpEventQueue();

    controller().start(sampleVideo, ScriptLanguage.english);
    await pumpEventQueue();

    expect(pipeline.started, [ScriptLanguage.urdu]);
  });

  test('restart_runs_once_previous_run_stopped', () async {
    controller().start(sampleVideo, ScriptLanguage.urdu);
    await pumpEventQueue();
    controller().start(sampleVideo, ScriptLanguage.english);

    pipeline.gate.complete();
    await pumpEventQueue();

    expect(pipeline.started, [ScriptLanguage.urdu, ScriptLanguage.english]);
  });

  test('cancel_while_waiting_never_starts_next_run', () async {
    controller().start(sampleVideo, ScriptLanguage.urdu);
    await pumpEventQueue();
    controller()
      ..start(sampleVideo, ScriptLanguage.english)
      ..cancel();

    pipeline.gate.complete();
    await pumpEventQueue();

    expect(pipeline.started, [ScriptLanguage.urdu]);
  });

  test('new_reel_drops_previous_run_result', () async {
    container.read(reelDraftProvider.notifier).setVideo(sampleVideo);
    controller().start(sampleVideo, ScriptLanguage.urdu);
    await pumpEventQueue();

    container.read(reelDraftProvider.notifier).startNew();
    pipeline.gate.complete();
    await pumpEventQueue();

    expect(container.read(reelDraftProvider).transcript, isNull);
  });

  group('in the background', () {
    late ControlledPipeline controlled;
    final writing = ScriptProgress(
      stage: ScriptStage.transcribing,
      fraction: 0.5,
      transcript: fixture,
    );

    setUp(() {
      controlled = ControlledPipeline();
      container = containerWith(controlled);
    });

    test('running_script_keeps_the_app_in_the_background', () async {
      controller().start(sampleVideo, ScriptLanguage.urdu);
      await pumpEventQueue();

      controlled.events.add(writing);
      await pumpEventQueue();

      expect(background.isRunning, isTrue);
    });

    test('cancelled_script_stops_the_background_service', () async {
      controller().start(sampleVideo, ScriptLanguage.urdu);
      await pumpEventQueue();
      controlled.events.add(writing);
      await pumpEventQueue();

      controller().cancel();
      await pumpEventQueue();

      expect(background.serviceCalls, ['show', 'stop']);
    });
  });
}
