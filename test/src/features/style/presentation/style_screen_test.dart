import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

Future<void> pumpStyle(WidgetTester tester) => pumpRoutes(tester, [
  AppRoutes.style,
], setup: TestSetup(overrides: [draftOverride(pickedDraft)]));

/// Scrolls [label] into view, then taps it.
Future<void> tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  testWidgets('fill_options_hidden_for_16_9', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, '16:9');

    expect(find.text('Blur background'), findsNothing);
  });

  testWidgets('free_preset_shows_crop_editor', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, 'Free');

    expect(
      find.text('Drag to move. Drag the corner to resize.'),
      findsOneWidget,
    );
  });

  testWidgets('branding_moves_to_bottom_when_caption_on_top', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, 'Top');

    expect(
      tester.getCenter(find.text('Status Studio').last).dy,
      greaterThan(tester.getCenter(find.byType(ReelPreview)).dy),
    );
  });

  testWidgets('size_hint_shows_output_size', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, '4:5');

    expect(
      find.text('Instagram and Facebook posts · 1080 × 1350'),
      findsOneWidget,
    );
  });

  testWidgets('blur_background_hides_keep_in_view', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, 'Blur background');

    expect(find.text('Keep in view'), findsNothing);
  });

  testWidgets('caption_starts_with_selected_lines', (tester) async {
    await pumpStyle(tester);

    final field = tester.widget<TextField>(find.byType(TextField));

    expect(field.controller!.text, pickedDraft.caption.text);
  });

  testWidgets('roman_variant_offered_for_urdu_transcript', (tester) async {
    await pumpStyle(tester);

    expect(find.text('Roman'), findsOneWidget);
  });

  testWidgets('export_reel_opens_export', (tester) async {
    await pumpStyle(tester);

    await tester.tap(find.text('Export reel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Export reel'), findsNothing);
  });

  testWidgets('tapping_selected_variant_keeps_caption_edits', (tester) async {
    await pumpStyle(tester);
    await tester.enterText(find.byType(TextField), 'My own words');

    await tapText(tester, 'Original');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'My own words');
  });

  testWidgets('switching_variant_replaces_caption_edits', (tester) async {
    await pumpStyle(tester);
    await tester.enterText(find.byType(TextField), 'My own words');

    await tapText(tester, 'English');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, pickedDraft.caption.text);
  });
}
