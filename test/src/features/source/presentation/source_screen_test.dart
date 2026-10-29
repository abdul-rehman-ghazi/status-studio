import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  testWidgets('invalid_link_shows_error', (tester) async {
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('Get the script'));
    await tester.pump();

    expect(find.text("That doesn't look like a YouTube link."), findsOneWidget);
  });

  testWidgets('valid_link_shows_video_title', (tester) async {
    await openSource(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await tester.pumpAndSettle();

    expect(find.text('Sample video'), findsOneWidget);
  });

  testWidgets('paste_fills_link_from_clipboard', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'https://youtu.be/dQw4w9WgXcQ'}
          : null,
    );
    await openSource(tester);

    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(find.text('Sample video'), findsOneWidget);
  });
}
