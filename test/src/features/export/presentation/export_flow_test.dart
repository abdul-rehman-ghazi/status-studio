import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/export/application/fake_renderer.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

/// Opens Export on top of Style, as the flow does.
Future<void> pumpExport(WidgetTester tester, {required Renderer renderer}) =>
    pumpRoutes(
      tester,
      [AppRoutes.style, AppRoutes.export],
      setup: TestSetup(
        overrides: [draftOverride(pickedDraft)],
        renderer: renderer,
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
    await pumpExport(tester, renderer: const FakeRenderer(step: Duration.zero));

    await tester.pumpAndSettle();

    expect(find.text('Reel ready'), findsOneWidget);
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

  testWidgets('done_shows_size_length_and_format', (tester) async {
    await pumpExport(tester, renderer: const FakeRenderer(step: Duration.zero));

    await tester.pumpAndSettle();

    expect(find.text('1080 × 1920 · 27.4 s · MP4'), findsOneWidget);
  });

  testWidgets('make_another_returns_home', (tester) async {
    await pumpExport(tester, renderer: const FakeRenderer(step: Duration.zero));
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
}
