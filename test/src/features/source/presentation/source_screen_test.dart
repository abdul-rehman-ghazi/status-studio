import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

import '../../../../helpers/pump_app.dart';

class UnavailableVideoSource extends FakeVideoSource {
  const UnavailableVideoSource();

  @override
  Future<SourceVideo> fetchVideo(String videoId) async =>
      throw const VideoUnavailableException('private');
}

class OfflineVideoSource extends FakeVideoSource {
  const OfflineVideoSource();

  @override
  Future<SourceVideo> fetchVideo(String videoId) async =>
      throw const OfflineException('no network');
}

Future<void> enterValidLink(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextField),
    'https://youtu.be/dQw4w9WgXcQ',
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('unavailable_video_shows_error', (tester) async {
    await openSource(
      tester,
      setup: const TestSetup(videoSource: UnavailableVideoSource()),
    );

    await enterValidLink(tester);

    expect(find.text("This video can't be downloaded."), findsOneWidget);
  });

  testWidgets('offline_shows_error', (tester) async {
    await openSource(
      tester,
      setup: const TestSetup(videoSource: OfflineVideoSource()),
    );

    await enterValidLink(tester);

    expect(find.text("You're offline. Connect and try again."), findsOneWidget);
  });

  testWidgets('get_the_script_stays_put_when_video_failed', (tester) async {
    await openSource(
      tester,
      setup: const TestSetup(videoSource: UnavailableVideoSource()),
    );
    await enterValidLink(tester);

    await tester.tap(find.text('Get the script'));
    await tester.pumpAndSettle();

    expect(find.text('Get the script'), findsOneWidget);
  });
}
