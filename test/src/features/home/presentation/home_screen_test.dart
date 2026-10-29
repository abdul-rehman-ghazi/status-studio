import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets('home_shows_new_reel_button', (tester) async {
    await pumpApp(tester);

    expect(find.text('New reel'), findsOneWidget);
  });

  testWidgets('new_reel_opens_source_screen', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('New reel'));
    await tester.pumpAndSettle();

    expect(find.text('YouTube link'), findsOneWidget);
  });

  testWidgets('home_shows_empty_recent_section', (tester) async {
    await pumpApp(tester);

    expect(find.text('Your reels will appear here.'), findsOneWidget);
  });

  testWidgets('settings_button_opens_settings', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });
}
