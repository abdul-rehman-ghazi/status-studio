import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/app.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const StatusStudioApp()),
  );
}

/// Opens the Source screen the way a user does: Home → New reel.
Future<void> openSource(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await pumpApp(tester, overrides: overrides);
  await tester.tap(find.text('New reel'));
  await tester.pumpAndSettle();
}
