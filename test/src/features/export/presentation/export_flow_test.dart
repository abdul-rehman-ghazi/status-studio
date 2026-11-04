import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/features/export/application/fake_renderer.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/library/data/recent_reels_repository.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_background_work_platform.dart';
import '../../../../helpers/fine_tune_drafts.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

/// Opens Export on top of Style, as the flow does.
Future<void> pumpExport(
  WidgetTester tester, {
  required Renderer renderer,
  FakeBackgroundWorkPlatform? background,
  RecordingFineTuneDraftSaver? fineTuneSaver,
}) => pumpRoutes(
  tester,
  [AppRoutes.style, AppRoutes.export],
  setup: TestSetup(
    overrides: [draftOverride(pickedDraft)],
    renderer: renderer,
    backgroundWork: background,
    fineTuneSaver: fineTuneSaver,
  ),
);

/// Renders like a slow fake and counts how often it is cancelled.
class SpyRenderer implements Renderer {
  var cancelCount = 0;

  @override
  Stream<RenderProgress> render(ReelDraft draft) =>
      const FakeRenderer(step: Duration(seconds: 1)).render(draft);

  @override
  Future<void> cancel() async => cancelCount++;
}

/// Finishes at once with a real MP4 file, as Media3 would leave one.
class FileRenderer implements Renderer {
  FileRenderer(this.folder);

  final Directory folder;

  @override
  Stream<RenderProgress> render(ReelDraft draft) async* {
    // Synchronous: real file I/O doesn't complete inside widget tests.
    final video = File('${folder.path}/reel_1.mp4')..writeAsStringSync('mp4');
    yield RenderFinished(video.path);
  }

  @override
  Future<void> cancel() async {}
}

/// Can't record anything, as when preferences can't be written.
class UnwritableRecentReels extends RecentReelsRepository {
  UnwritableRecentReels() : super(SharedPreferencesAsync());

  @override
  Future<void> add(RecentReel reel) async =>
      throw const FileSystemException('Write failed');
}

/// Fails every render the way a native Media3 error does.
class FailingRenderer implements Renderer {
  var renders = 0;

  @override
  Stream<RenderProgress> render(ReelDraft draft) {
    renders++;
    return Stream.error(const RenderFailedException('codec failed'));
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  testWidgets('export_finishes_on_done_screen', (tester) async {
    final folder = Directory.systemTemp.createTempSync('export_flow_test');
    addTearDown(() => folder.deleteSync(recursive: true));
    await pumpExport(tester, renderer: FileRenderer(folder));

    await tester.pumpAndSettle();

    expect(find.text('Reel ready'), findsOneWidget);
  });

  testWidgets('a_finished_export_discards_the_kept_fine_tune', (tester) async {
    final folder = Directory.systemTemp.createTempSync('export_flow_test');
    addTearDown(() => folder.deleteSync(recursive: true));
    final saver = RecordingFineTuneDraftSaver();
    await pumpExport(
      tester,
      renderer: FileRenderer(folder),
      fineTuneSaver: saver,
    );

    await tester.pumpAndSettle();

    expect(saver.discarded.single, pickedDraft);
  });

  testWidgets('a_cancelled_export_keeps_it', (tester) async {
    final saver = RecordingFineTuneDraftSaver();
    await pumpExport(
      tester,
      renderer: const FakeRenderer(step: Duration(seconds: 1)),
      fineTuneSaver: saver,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saver.discarded, isEmpty);
  });

  testWidgets('cancel_export_returns_to_style', (tester) async {
    await pumpExport(
      tester,
      renderer: const FakeRenderer(step: Duration(seconds: 1)),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Export reel'), findsOneWidget);
  });

  testWidgets('export_shows_progress_percentage', (tester) async {
    await pumpExport(
      tester,
      renderer: const FakeRenderer(step: Duration(seconds: 1)),
    );

    await tester.pump(const Duration(seconds: 1));

    expect(find.text('4%'), findsOneWidget);
  });

  testWidgets('export_summarises_the_reel', (tester) async {
    await pumpExport(
      tester,
      renderer: const FakeRenderer(step: Duration(seconds: 1)),
    );

    expect(find.text('Cropped at 1080 × 1920'), findsOneWidget);
  });

  testWidgets('make_another_returns_home', (tester) async {
    final folder = Directory.systemTemp.createTempSync('export_flow_test');
    addTearDown(() => folder.deleteSync(recursive: true));
    await pumpExport(tester, renderer: FileRenderer(folder));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Make another'));
    await tester.pumpAndSettle();

    expect(find.text('New reel'), findsOneWidget);
  });

  testWidgets('system_back_on_export_cancels_render', (tester) async {
    final renderer = SpyRenderer();
    await pumpExport(tester, renderer: renderer);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(renderer.cancelCount, 1);
  });

  testWidgets('system_back_on_export_returns_to_style', (tester) async {
    await pumpExport(tester, renderer: SpyRenderer());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Export reel'), findsOneWidget);
  });

  testWidgets('failed_render_shows_message', (tester) async {
    await pumpExport(tester, renderer: FailingRenderer());

    expect(find.text("Couldn't make the reel."), findsOneWidget);
  });

  testWidgets('retry_after_failed_render_renders_again', (tester) async {
    final renderer = FailingRenderer();
    await pumpExport(tester, renderer: renderer);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(renderer.renders, 2);
  });

  testWidgets('back_after_failed_render_returns_to_style', (tester) async {
    await pumpExport(tester, renderer: FailingRenderer());

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Export reel'), findsOneWidget);
  });

  testWidgets('failure_to_record_the_reel_offers_retry', (tester) async {
    await pumpRoutes(
      tester,
      [AppRoutes.style, AppRoutes.export],
      setup: TestSetup(
        overrides: [
          draftOverride(pickedDraft),
          recentReelsRepositoryProvider.overrideWithValue(
            UnwritableRecentReels(),
          ),
        ],
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('rendering_keeps_the_app_in_the_background', (tester) async {
    final background = FakeBackgroundWorkPlatform();
    await pumpExport(
      tester,
      renderer: const FakeRenderer(step: Duration(seconds: 1)),
      background: background,
    );

    await tester.pump(const Duration(seconds: 1));

    expect(background.isRunning, isTrue);
  });

  testWidgets('cancelled_export_stops_the_background_service', (tester) async {
    final background = FakeBackgroundWorkPlatform();
    await pumpExport(
      tester,
      renderer: const FakeRenderer(step: Duration(seconds: 1)),
      background: background,
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(background.serviceCalls.last, 'stop');
  });
}
