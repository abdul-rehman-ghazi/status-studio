import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

const _keyName = 'groq.apiKey';

/// The user's Groq key (spec FR-12a), kept only in the Android Keystore.
/// A saved key is what lets Groq write scripts; removing it turns that off.
class GroqKeyStore {
  GroqKeyStore(this._vault);

  final FlutterSecureStorage _vault;

  Future<bool> hasKey() async => await _vault.read(key: _keyName) != null;

  /// Throws [NoGroqKeyException] when no key is saved.
  Future<String> savedKey() async {
    final key = await _vault.read(key: _keyName);
    if (key == null) {
      throw const NoGroqKeyException();
    }
    return key;
  }

  Future<void> saveKey(String apiKey) =>
      _vault.write(key: _keyName, value: apiKey.trim());

  Future<void> removeKey() => _vault.delete(key: _keyName);
}

final groqKeyStoreProvider = Provider<GroqKeyStore>(
  (ref) => GroqKeyStore(const FlutterSecureStorage()),
);
