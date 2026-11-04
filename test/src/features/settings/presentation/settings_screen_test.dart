import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fake_yt_dlp.dart';
import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets('settings_shows_yt_dlp_version', (tester) async {
    await pumpRoutes(tester, [AppRoutes.settings]);
    await tester.scrollUntilVisible(
      find.text('yt-dlp 2026.10.26'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('yt-dlp 2026.10.26'), findsOneWidget);
  });

  testWidgets('update_button_updates_yt_dlp', (tester) async {
    final ytDlp = FakeYtDlp();
    await pumpRoutes(tester, [
      AppRoutes.settings,
    ], setup: TestSetup(ytDlp: ytDlp));
    await tester.scrollUntilVisible(
      find.text('Update'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(ytDlp.updates, 1);
  });

  testWidgets('settings_offers_the_groq_key_first', (tester) async {
    await pumpRoutes(tester, [AppRoutes.settings]);

    expect(find.text('Groq API key'), findsOneWidget);
  });
}
