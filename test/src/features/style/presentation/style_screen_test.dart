import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/data/caption_translator.dart';
import 'package:status_studio/src/features/style/domain/roman_urdu.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_caption_translator.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

Future<void> pumpStyle(
  WidgetTester tester, {
  ReelDraft? draft,
  CaptionTranslator translator = const FakeCaptionTranslator(),
}) => pumpRoutes(
  tester,
  [AppRoutes.style],
  setup: TestSetup(
    overrides: [draftOverride(draft ?? pickedDraft)],
    translator: translator,
  ),
);

/// Translates only when [gate] completes; fails with [failure] if set.
class SlowTranslator extends FakeCaptionTranslator {
  SlowTranslator({this.failure});

  final gate = Completer<void>();
  final Exception? failure;

  @override
  Future<String> toEnglish(String text, String languageCode) async {
    await gate.future;
    if (failure case final failure?) {
      throw failure;
    }
    return super.toEnglish(text, languageCode);
  }
}

/// The picked draft with its transcript marked as [languageCode].
ReelDraft pickedIn(String languageCode) => pickedDraft.copyWith(
  transcript: pickedDraft.transcript!.copyWith(languageCode: languageCode),
);

/// Scrolls [label] into view, then taps it.
Future<void> tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  testWidgets('branding_moves_to_bottom_when_caption_on_top', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, 'Top');

    expect(
      tester.getCenter(find.text('Status Studio').last).dy,
      greaterThan(tester.getCenter(find.byType(ReelPreview)).dy),
    );
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
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'EN: ${pickedDraft.caption.text}');
  });

  testWidgets('roman_hidden_for_non_urdu', (tester) async {
    await pumpStyle(tester, draft: pickedIn('hi'));

    expect(find.text('Roman'), findsNothing);
  });

  testWidgets('english_hidden_when_translation_unsupported', (tester) async {
    await pumpStyle(tester, draft: pickedIn('pa'));

    expect(find.text('English'), findsNothing);
  });

  testWidgets('switching_variant_replaces_text', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, 'Roman');
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, romanizeUrdu(pickedDraft.caption.text));
  });

  testWidgets('english_variant_uses_translation', (tester) async {
    await pumpStyle(tester);

    await tapText(tester, 'English');
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, startsWith('EN: '));
  });

  testWidgets('translating_shows_progress', (tester) async {
    await pumpStyle(tester, translator: SlowTranslator());

    await tapText(tester, 'English');

    expect(find.text('Translating…'), findsOneWidget);
  });

  testWidgets('late_translation_does_not_replace_later_choice', (tester) async {
    final translator = SlowTranslator();
    await pumpStyle(tester, translator: translator);
    await tapText(tester, 'English');

    await tapText(tester, 'Roman');
    translator.gate.complete();
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, romanizeUrdu(pickedDraft.caption.text));
  });

  testWidgets('translation_failure_shows_message', (tester) async {
    final translator = SlowTranslator(
      failure: PlatformException(code: 'translate_failed'),
    );
    await pumpStyle(tester, translator: translator);
    await tapText(tester, 'English');

    translator.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
  });
}
