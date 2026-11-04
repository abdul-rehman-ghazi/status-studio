import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/app.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

import '../../../../helpers/counting_video_source.dart';
import '../../../../helpers/pump_app.dart';

Future<void> startProcessing(
  WidgetTester tester, {
  required Duration step,
  VideoSource videoSource = const FakeVideoSource(),
  ScriptPipeline? pipeline,
}) async {
  await openSource(
    tester,
    setup: TestSetup(
      videoSource: videoSource,
      scriptPipeline: pipeline ?? FakeScriptPipeline(step: step),
    ),
  );
  await tester.enterText(
    find.byType(TextField),
    'https://youtu.be/dQw4w9WgXcQ',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Get the script'));
}

/// Fails every run with [error].
class FailingPipeline extends FakeScriptPipeline {
  const FailingPipeline(this.error);

  final Object error;

  @override
  Stream<ScriptProgress> run(SourceVideo video, ScriptLanguage language) =>
      Stream.error(error);
}

/// Sends whatever the test adds to [events], so the screen is up before
/// the run reports anything, as it is while the audio downloads.
class ManualPipeline extends FakeScriptPipeline {
  ManualPipeline();

  final events = StreamController<ScriptProgress>();

  @override
  Stream<ScriptProgress> run(SourceVideo video, ScriptLanguage language) =>
      events.stream;
}

void main() {
  testWidgets('processing_opens_script_when_done', (tester) async {
    await startProcessing(tester, step: Duration.zero);

    await tester.pumpAndSettle();

    expect(find.text('Pick the lines'), findsOneWidget);
  });

  testWidgets('processing_shows_the_steps', (tester) async {
    await startProcessing(tester, step: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Lining up timestamps'), findsOneWidget);
  });

  group('step amounts', () {
    late ManualPipeline pipeline;
    final empty = sampleTranscript.copyWith(lines: const []);

    ScriptProgress audioDownload(int done) => ScriptProgress(
      stage: ScriptStage.downloadingAudio,
      fraction: 0.2,
      transcript: empty,
      step: WorkAmount(done: done, total: 3300000, unit: WorkUnit.bytes),
    );

    Future<void> openWith(WidgetTester tester) async {
      pipeline = ManualPipeline();
      await startProcessing(tester, step: Duration.zero, pipeline: pipeline);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('current_step_shows_its_sizes', (tester) async {
      await openWith(tester);

      pipeline.events.add(audioDownload(1100000));
      await tester.pump();

      expect(find.textContaining('1.1 of 3.3 MB'), findsOneWidget);
    });

    testWidgets('current_step_shows_its_percent', (tester) async {
      await openWith(tester);

      pipeline.events.add(audioDownload(1100000));
      await tester.pump();

      expect(find.text('33 %'), findsOneWidget);
    });

    testWidgets('current_step_fills_its_own_bar', (tester) async {
      await openWith(tester);

      pipeline.events.add(audioDownload(1100000));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is LinearProgressIndicator && widget.value == 1 / 3,
        ),
        findsOneWidget,
      );
    });

    testWidgets('step_underway_shows_time_left', (tester) async {
      await openWith(tester);
      pipeline.events.add(audioDownload(1100000));
      await tester.pump();

      pipeline.events.add(audioDownload(2200000));
      await tester.pump();

      expect(find.textContaining(' left'), findsOneWidget);
    });

    testWidgets('finished_step_shows_no_time_left', (tester) async {
      await openWith(tester);
      pipeline.events.add(audioDownload(1100000));
      await tester.pump();

      pipeline.events.add(audioDownload(3300000));
      await tester.pump();

      expect(find.textContaining(' left'), findsNothing);
    });

    testWidgets('finished_step_keeps_its_amount', (tester) async {
      await openWith(tester);
      pipeline.events.add(audioDownload(3300000));
      await tester.pump();

      pipeline.events.add(
        ScriptProgress(
          stage: ScriptStage.detectingLanguage,
          fraction: 0.35,
          transcript: empty,
        ),
      );
      await tester.pump();

      expect(find.textContaining('3.3 of 3.3 MB'), findsOneWidget);
    });

    testWidgets('writing_shows_audio_done_of_the_length', (tester) async {
      await openWith(tester);

      pipeline.events.add(
        ScriptProgress(
          stage: ScriptStage.transcribing,
          fraction: 0.5,
          transcript: empty,
          step: const WorkAmount(
            done: 180000,
            total: 548000,
            unit: WorkUnit.audioMilliseconds,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('3:00 of 9:08'), findsOneWidget);
    });
  });

  testWidgets('cancel_processing_returns_to_source', (tester) async {
    await startProcessing(tester, step: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Get the script'), findsOneWidget);
  });

  testWidgets('system_back_cancels_run', (tester) async {
    await startProcessing(tester, step: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StatusStudioApp)),
    );
    expect(container.read(reelDraftProvider).transcript, isNull);
  });

  testWidgets('processing_does_not_download_video', (tester) async {
    final videoSource = CountingVideoSource();
    await startProcessing(
      tester,
      step: Duration.zero,
      videoSource: videoSource,
    );

    await tester.pumpAndSettle();

    expect(videoSource.prepareCount, 0);
  });

  testWidgets('first_line_offers_start_picking_lines', (tester) async {
    await startProcessing(tester, step: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Start picking lines'), findsOneWidget);
  });

  testWidgets('no_speech_shows_message_and_other_language', (tester) async {
    await startProcessing(
      tester,
      step: Duration.zero,
      pipeline: const FailingPipeline(NoSpeechFoundException()),
    );
    await tester.pumpAndSettle();

    expect(
      [
        find.text('No speech found in this video.'),
        find.text('Try another language'),
      ].map((finder) => finder.evaluate().length),
      [1, 1],
    );
  });

  group('groq_errors', () {
    Future<void> failWith(WidgetTester tester, Object error) async {
      await startProcessing(
        tester,
        step: Duration.zero,
        pipeline: FailingPipeline(error),
      );
      await tester.pumpAndSettle();
    }

    List<String> offeredActions() => [
      for (final label in ['Retry', 'Settings', 'Back'])
        if (find.widgetWithText(OutlinedButton, label).evaluate().isNotEmpty)
          label,
    ];

    testWidgets('rejected_key_offers_settings_and_back', (tester) async {
      await failWith(tester, const GroqKeyRejectedException());

      expect(offeredActions(), ['Settings', 'Back']);
    });

    testWidgets('missing_key_offers_settings_and_back', (tester) async {
      await failWith(tester, const NoGroqKeyException());

      expect(offeredActions(), ['Settings', 'Back']);
    });

    testWidgets('missing_key_message_is_shown', (tester) async {
      await failWith(tester, const NoGroqKeyException());

      expect(
        find.text('Writing a script needs a free Groq key.'),
        findsOneWidget,
      );
    });

    testWidgets('rate_limit_offers_back_only', (tester) async {
      await failWith(
        tester,
        const GroqRateLimitedException(Duration(minutes: 5)),
      );

      expect(offeredActions(), ['Back']);
    });

    testWidgets('groq_failure_offers_retry_and_back', (tester) async {
      await failWith(tester, const GroqFailedException(500));

      expect(offeredActions(), ['Retry', 'Back']);
    });

    testWidgets('groq_offline_offers_retry_and_back', (tester) async {
      await failWith(tester, const GroqOfflineException());

      expect(offeredActions(), ['Retry', 'Back']);
    });

    testWidgets('rejected_key_message_is_shown', (tester) async {
      await failWith(tester, const GroqKeyRejectedException());

      expect(find.text("Groq didn't accept your API key."), findsOneWidget);
    });

    testWidgets('settings_action_opens_settings', (tester) async {
      await failWith(tester, const GroqKeyRejectedException());

      await tester.tap(find.widgetWithText(OutlinedButton, 'Settings'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    });

    testWidgets('back_action_leaves_processing', (tester) async {
      await failWith(tester, const GroqFailedException(500));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
      await tester.pumpAndSettle();

      expect(find.text('Working'), findsNothing);
    });
  });
}
