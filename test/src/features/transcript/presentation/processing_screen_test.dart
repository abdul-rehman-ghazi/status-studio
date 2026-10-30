import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';

import '../../../../helpers/counting_video_source.dart';
import '../../../../helpers/pump_app.dart';

Future<void> startProcessing(
  WidgetTester tester, {
  required Duration step,
  VideoSource videoSource = const FakeVideoSource(),
}) async {
  await openSource(
    tester,
    setup: TestSetup(
      videoSource: videoSource,
      overrides: [
        scriptPipelineProvider.overrideWithValue(
          FakeScriptPipeline(step: step),
        ),
      ],
    ),
  );
  await tester.enterText(
    find.byType(TextField),
    'https://youtu.be/dQw4w9WgXcQ',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Get the script'));
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

  testWidgets('processing_prepares_the_source_video', (tester) async {
    final videoSource = CountingVideoSource();
    await startProcessing(
      tester,
      step: Duration.zero,
      videoSource: videoSource,
    );

    await tester.pumpAndSettle();

    expect(videoSource.prepareCount, 1);
  });
}
