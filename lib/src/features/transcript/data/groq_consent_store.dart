import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

const _consentKey = 'groq.uploadConsent';

/// Whether the user agreed that the app sends their audio, and Fix with
/// Groq's lines, to Groq (spec FR-30). Only an agreement is kept: "Not now"
/// stores nothing, so the user is asked again the next time.
class GroqConsentStore {
  const GroqConsentStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  Future<bool> isGiven() async =>
      await _preferences.getBool(_consentKey) ?? false;

  /// Throws [NoGroqConsentException] unless the user has agreed.
  Future<void> requireGiven() async {
    if (!await isGiven()) {
      throw const NoGroqConsentException();
    }
  }

  Future<void> give() => _preferences.setBool(_consentKey, true);

  Future<void> withdraw() => _preferences.remove(_consentKey);
}

final groqConsentStoreProvider = Provider<GroqConsentStore>(
  (ref) => GroqConsentStore(ref.watch(preferencesProvider)),
);
