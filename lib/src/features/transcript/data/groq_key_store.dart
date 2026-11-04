import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

const _keyName = 'groq.apiKey';
const _enabledName = 'settings.groqEnabled';

/// The user's Groq key and the "Write scripts with Groq" switch (spec
/// FR-12a). The key lives only in the Android Keystore; the switch is an
/// ordinary preference that can be on only while a key is saved.
class GroqKeyStore {
  GroqKeyStore(this._vault, this._preferences);

  final FlutterSecureStorage _vault;
  final SharedPreferencesAsync _preferences;

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

  /// Removing the key also turns the switch off.
  Future<void> removeKey() async {
    await _vault.delete(key: _keyName);
    await _preferences.setBool(_enabledName, false);
  }

  Future<bool> isEnabled() async {
    final switchedOn = await _preferences.getBool(_enabledName) ?? false;
    return switchedOn && await hasKey();
  }

  /// Throws [NoGroqKeyException] when turning it on without a key.
  Future<void> setEnabled(bool enabled) async {
    if (enabled && !await hasKey()) {
      throw const NoGroqKeyException();
    }
    await _preferences.setBool(_enabledName, enabled);
  }
}

final groqKeyStoreProvider = Provider<GroqKeyStore>(
  (ref) => GroqKeyStore(
    const FlutterSecureStorage(),
    ref.watch(preferencesProvider),
  ),
);
