import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/settings/application/groq_settings_controller.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

void main() {
  late GroqKeyStore store;
  late ProviderContainer container;
  Object? rejection;
  final checked = <String>[];

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    store = GroqKeyStore(const FlutterSecureStorage());
    rejection = null;
    checked.clear();
    container = ProviderContainer.test(
      overrides: [
        groqKeyStoreProvider.overrideWithValue(store),
        groqKeyCheckerProvider.overrideWithValue((apiKey) async {
          checked.add(apiKey);
          if (rejection case final error?) {
            throw error;
          }
        }),
      ],
    );
  });

  GroqKeyController controller() =>
      container.read(groqKeySavedProvider.notifier);

  Future<bool> keySaved() => container.read(groqKeySavedProvider.future);

  test('save_key_checks_the_key_before_saving', () async {
    await keySaved();

    await controller().saveKey('gsk_good');

    expect(checked, ['gsk_good']);
  });

  test('save_key_stores_a_key_that_works', () async {
    await keySaved();

    await controller().saveKey('gsk_good');

    expect(await store.savedKey(), 'gsk_good');
  });

  test('save_key_keeps_the_old_key_when_the_new_one_is_rejected', () async {
    await store.saveKey('gsk_old');
    await keySaved();
    rejection = const GroqKeyRejectedException();

    await expectLater(
      controller().saveKey('gsk_bad'),
      throwsA(isA<GroqKeyRejectedException>()),
    );

    expect(await store.savedKey(), 'gsk_old');
  });

  test('remove_key_forgets_the_key', () async {
    await store.saveKey('gsk_good');
    await keySaved();

    await controller().removeKey();

    expect(await keySaved(), isFalse);
  });

  test('settings_start_from_the_saved_key', () async {
    await store.saveKey('gsk_good');

    expect(await keySaved(), isTrue);
  });

  test('save_key_marks_a_key_as_saved', () async {
    await keySaved();

    await controller().saveKey('gsk_good');

    expect(await keySaved(), isTrue);
  });
}
