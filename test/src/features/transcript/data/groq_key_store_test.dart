import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

void main() {
  late GroqKeyStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    store = GroqKeyStore(const FlutterSecureStorage());
  });

  test('saved_key_is_returned_trimmed', () async {
    await store.saveKey('  gsk_abc \n');

    expect(await store.savedKey(), 'gsk_abc');
  });

  test('saved_key_throws_when_none_is_saved', () {
    expect(store.savedKey(), throwsA(isA<NoGroqKeyException>()));
  });

  test('has_key_is_false_until_a_key_is_saved', () async {
    expect(await store.hasKey(), isFalse);
  });

  test('removed_key_is_gone', () async {
    await store.saveKey('gsk_abc');

    await store.removeKey();

    expect(store.savedKey(), throwsA(isA<NoGroqKeyException>()));
  });
}
