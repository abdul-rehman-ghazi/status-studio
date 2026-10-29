import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/app.dart';

void main() {
  testWidgets('app_starts_on_home_screen_showing_app_name', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: StatusStudioApp()));

    expect(find.text('Status Studio'), findsOneWidget);
  });
}
