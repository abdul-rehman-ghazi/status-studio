import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

Future<void> pumpFineTune(WidgetTester tester) => pumpRoutes(tester, [
  AppRoutes.fineTune,
], setup: TestSetup(overrides: [draftOverride(pickedDraft)]));

void main() {
  testWidgets('nudge_start_updates_label', (tester) async {
    await pumpFineTune(tester);

    await tester.tap(find.bySemanticsLabel('Start half a second earlier'));
    await tester.pump();

    expect(find.text('0:20.9'), findsOneWidget);
  });

  testWidgets('nudge_end_later_updates_label', (tester) async {
    await pumpFineTune(tester);

    await tester.tap(find.bySemanticsLabel('End half a second later'));
    await tester.pump();

    expect(find.text('0:49.3'), findsOneWidget);
  });

  testWidgets('shows_clip_length', (tester) async {
    await pumpFineTune(tester);

    expect(find.text('27.4 s'), findsOneWidget);
  });

  testWidgets('lists_the_lines_in_the_clip', (tester) async {
    await pumpFineTune(tester);

    expect(find.text('محنت کامیابی کی کنجی ہے'), findsOneWidget);
  });
}
