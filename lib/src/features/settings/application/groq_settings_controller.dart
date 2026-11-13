import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/application/groq_usage_controller.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_consent_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';

/// Asks Groq whether [apiKey] is accepted; throws a `Groq…Exception` if not.
/// A provider so tests never reach the network.
final groqKeyCheckerProvider = Provider<Future<void> Function(String apiKey)>(
  (ref) =>
      (apiKey) => GroqClient(
        apiKey: apiKey.trim(),
        beforeUpload: ref.read(groqConsentStoreProvider).requireGiven,
      ).checkKey(),
);

/// Whether a Groq key is saved (spec FR-12a). A saved key has always
/// passed the check, because `saveKey` checks before it saves.
final groqKeySavedProvider = AsyncNotifierProvider<GroqKeyController, bool>(
  GroqKeyController.new,
);

class GroqKeyController extends AsyncNotifier<bool> {
  GroqKeyStore get _store => ref.read(groqKeyStoreProvider);

  @override
  Future<bool> build() => _store.hasKey();

  /// Saves [apiKey] only once Groq accepts it, so a wrong key never
  /// replaces a good one. Throws what the check throws.
  Future<void> saveKey(String apiKey) async {
    await ref.read(groqKeyCheckerProvider)(apiKey);
    await _store.saveKey(apiKey);
    await ref.read(groqUsageProvider.notifier).forget();
    state = const AsyncData(true);
  }

  Future<void> removeKey() async {
    await _store.removeKey();
    await ref.read(groqUsageProvider.notifier).forget();
    state = const AsyncData(false);
  }
}
