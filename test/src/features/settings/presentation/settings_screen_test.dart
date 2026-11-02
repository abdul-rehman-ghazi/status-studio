import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_model_manager.dart';
import '../../../../helpers/pump_app.dart';

Future<void> pumpSettings(WidgetTester tester, FakeModelManager models) =>
    pumpRoutes(tester, [
      AppRoutes.settings,
    ], setup: TestSetup(modelManager: models));

/// The row for [label], to find its status text and buttons.
Finder rowOf(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ListTile));

void main() {
  testWidgets('selecting_base_persists_setting', (tester) async {
    await pumpSettings(tester, FakeModelManager());

    await tester.tap(find.text('Base (faster)'));
    await tester.pumpAndSettle();

    final stored = await tester.runAsync(
      () => SharedPreferencesAsync().getString('settings.whisperModel'),
    );
    expect(stored, 'base');
  });

  testWidgets('download_shows_progress_then_size', (tester) async {
    final models = FakeModelManager()..gate = Completer<void>();
    await pumpSettings(tester, models);

    await tester.tap(
      find.descendant(
        of: rowOf('Base (faster)'),
        matching: find.text('Download'),
      ),
    );
    await tester.pump();
    final whileDownloading = find.text('Downloading… 50 %').evaluate().length;
    models.gate!.complete();
    await tester.pumpAndSettle();

    expect(
      (whileDownloading, find.text('148 MB on your phone').evaluate().length),
      (1, 1),
    );
  });

  testWidgets('reopened_settings_shows_running_download', (tester) async {
    final models = FakeModelManager()..gate = Completer<void>();
    await pumpSettings(tester, models);
    await tester.tap(
      find.descendant(
        of: rowOf('Base (faster)'),
        matching: find.text('Download'),
      ),
    );
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Downloading… 50 %'), findsOneWidget);
  });

  testWidgets('delete_returns_to_not_downloaded', (tester) async {
    final models = FakeModelManager(
      sizes: {SpeechModel.small: FakeModelManager.downloadedBytes},
    );
    await pumpSettings(tester, models);

    await tester.tap(
      find.descendant(
        of: rowOf('Small (better, slower)'),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not downloaded'), findsNWidgets(2));
  });

  testWidgets('switching_model_keeps_downloaded_files', (tester) async {
    final models = FakeModelManager(
      sizes: {
        SpeechModel.small: FakeModelManager.downloadedBytes,
        SpeechModel.base: FakeModelManager.downloadedBytes,
      },
    );
    await pumpSettings(tester, models);

    await tester.tap(find.text('Base (faster)'));
    await tester.pumpAndSettle();

    expect(
      (
        models.deleted.length,
        find.text('148 MB on your phone').evaluate().length,
      ),
      (0, 2),
    );
  });

  testWidgets('failed_download_offers_retry', (tester) async {
    final models = FakeModelManager()
      ..failure = const ModelDownloadException('HTTP 503');
    await pumpSettings(tester, models);

    await tester.tap(
      find.descendant(
        of: rowOf('Base (faster)'),
        matching: find.text('Download'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      (
        find.text("Couldn't download the speech model.").evaluate().length,
        find.text('Retry').evaluate().length,
      ),
      (1, 1),
    );
  });
}
