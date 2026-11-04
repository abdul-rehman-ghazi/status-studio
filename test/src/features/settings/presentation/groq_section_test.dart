import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/settings/application/groq_settings_controller.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/routing/app_router.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  late GroqKeyStore store;
  Object? rejection;
  final checked = <String>[];
  String? clipboard;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = GroqKeyStore(const FlutterSecureStorage());
    rejection = null;
    clipboard = null;
    checked.clear();
  });

  Future<void> openSettings(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
          return null;
        }
        return call.method == 'Clipboard.getData' ? {'text': clipboard} : null;
      },
    );
    await pumpRoutes(
      tester,
      [AppRoutes.settings],
      setup: TestSetup(
        overrides: [
          groqKeyStoreProvider.overrideWithValue(store),
          groqKeyCheckerProvider.overrideWithValue((apiKey) async {
            checked.add(apiKey);
            if (rejection case final error?) {
              throw error;
            }
          }),
        ],
      ),
    );
  }

  Future<void> saveKey(WidgetTester tester, String key) async {
    await tester.enterText(find.byType(TextField), key);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  bool obscured(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).obscureText;

  testWidgets('key_field_is_masked_until_show_is_tapped', (tester) async {
    await openSettings(tester);
    final before = obscured(tester);

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect((before, obscured(tester)), (true, false));
  });

  testWidgets('save_with_a_working_key_says_key_works', (tester) async {
    await openSettings(tester);

    await saveKey(tester, 'gsk_good');

    expect(find.text('Key works'), findsOneWidget);
  });

  testWidgets('save_stores_the_key', (tester) async {
    await openSettings(tester);

    await saveKey(tester, 'gsk_good');

    expect(await store.savedKey(), 'gsk_good');
  });

  testWidgets('rejected_key_says_so_and_is_not_saved', (tester) async {
    rejection = const GroqKeyRejectedException();
    await openSettings(tester);

    await saveKey(tester, 'gsk_bad');

    expect(find.text("Groq didn't accept this key."), findsOneWidget);
    expect(await store.hasKey(), isFalse);
  });

  testWidgets('offline_check_says_offline', (tester) async {
    rejection = const GroqOfflineException();
    await openSettings(tester);

    await saveKey(tester, 'gsk_any');

    expect(find.text("You're offline. Connect and try again."), findsOneWidget);
  });

  testWidgets('save_is_disabled_while_the_field_is_empty', (tester) async {
    await openSettings(tester);

    final save = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Save'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

    expect(save.onPressed, isNull);
  });

  testWidgets('paste_fills_the_field_from_the_clipboard', (tester) async {
    await openSettings(tester);
    clipboard = 'gsk_pasted';

    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'gsk_pasted'), findsOneWidget);
  });

  testWidgets('saved_key_reads_key_works_after_reopening', (tester) async {
    await store.saveKey('gsk_good');

    await openSettings(tester);

    expect(find.text('Key works'), findsOneWidget);
  });

  testWidgets('remove_offers_only_while_a_key_is_saved', (tester) async {
    await openSettings(tester);

    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('remove_forgets_the_key', (tester) async {
    await store.saveKey('gsk_good');
    await openSettings(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(await store.hasKey(), isFalse);
    expect(find.text('Key works'), findsNothing);
  });

  group('help sheet', () {
    Future<void> openHelp(WidgetTester tester) async {
      await openSettings(tester);
      await tester.tap(find.byTooltip('How to get a free Groq key'));
      await tester.pumpAndSettle();
    }

    testWidgets('info_button_opens_the_steps', (tester) async {
      await openHelp(tester);

      expect(find.text('How to get a free Groq key'), findsOneWidget);
      expect(find.textContaining('Create API Key'), findsOneWidget);
    });

    testWidgets('help_shows_the_free_plan_and_privacy_notes', (tester) async {
      await openHelp(tester);

      expect(
        find.text(
          'Free plan: about 2 hours of audio every hour, and 8 hours a day.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Keep the key private, like a password.'),
        findsOneWidget,
      );
    });

    testWidgets('copy_link_copies_the_keys_page', (tester) async {
      await openHelp(tester);

      await tester.tap(find.text('Copy link'));
      await tester.pump();

      expect(clipboard, 'console.groq.com/keys');
    });

    testWidgets('copy_link_says_link_copied', (tester) async {
      await openHelp(tester);

      await tester.tap(find.text('Copy link'));
      await tester.pump();

      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('done_closes_the_sheet', (tester) async {
      await openHelp(tester);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Create API Key'), findsNothing);
    });
  });
}
