import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
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

  testWidgets('cancel_processing_returns_to_source', (tester) async {
    await startProcessing(tester, step: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Get the script'), findsOneWidget);
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
}
