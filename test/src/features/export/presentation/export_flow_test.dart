import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/export/application/fake_renderer.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
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
        overrides: [
          draftOverride(pickedDraft),
          rendererProvider.overrideWithValue(renderer),
        ],
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

  testWidgets('save_says_it_comes_later', (tester) async {
    await pumpExport(tester, renderer: const FakeRenderer(step: Duration.zero));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Available in a later update'), findsOneWidget);
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
}
