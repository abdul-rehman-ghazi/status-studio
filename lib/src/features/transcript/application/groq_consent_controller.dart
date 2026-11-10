import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/data/groq_consent_store.dart';

/// Whether sending to Groq is allowed (spec FR-30), for the consent screen
/// and Settings. Uploads check [GroqConsentStore] themselves.
final groqConsentProvider = AsyncNotifierProvider<GroqConsentController, bool>(
  GroqConsentController.new,
);

class GroqConsentController extends AsyncNotifier<bool> {
  GroqConsentStore get _store => ref.read(groqConsentStoreProvider);

  @override
  Future<bool> build() => _store.isGiven();

  Future<void> give() async {
    await _store.give();
    state = const AsyncData(true);
  }

  Future<void> withdraw() async {
    await _store.withdraw();
    state = const AsyncData(false);
  }
}
