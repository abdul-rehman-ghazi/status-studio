import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

void main() {
  late GroqKeyStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = GroqKeyStore(
      const FlutterSecureStorage(),
      SharedPreferencesAsync(),
    );
  });

  test('saved_key_is_returned_trimmed', () async {
    await store.saveKey('  gsk_abc \n');

    expect(await store.savedKey(), 'gsk_abc');
  });

  test('saved_key_throws_when_none_is_saved', () {
    expect(store.savedKey(), throwsA(isA<NoGroqKeyException>()));
  });

  test('switch_cannot_be_turned_on_without_a_key', () {
    expect(store.setEnabled(true), throwsA(isA<NoGroqKeyException>()));
  });

  test('switch_stays_on_once_a_key_is_saved', () async {
    await store.saveKey('gsk_abc');

    await store.setEnabled(true);

    expect(await store.isEnabled(), isTrue);
  });

  test('removing_the_key_turns_the_switch_off', () async {
    await store.saveKey('gsk_abc');
    await store.setEnabled(true);

    await store.removeKey();

    expect(await store.isEnabled(), isFalse);
  });
}
