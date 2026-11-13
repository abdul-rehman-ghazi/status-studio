import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_consent_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';

/// Opens a Groq client for chat calls (topics, translation, words). The key
/// first, so a user without one is sent to Settings before being asked for
/// consent (as the script pipeline does); the client checks consent again
/// before every upload (FR-30).
typedef GroqChatClientOpener = Future<GroqClient> Function();

final groqChatClientProvider = Provider<GroqChatClientOpener>((ref) {
  return () async {
    final keys = ref.read(groqKeyStoreProvider);
    final consent = ref.read(groqConsentStoreProvider);
    final apiKey = await keys.savedKey();
    await consent.requireGiven();
    return GroqClient(apiKey: apiKey, beforeUpload: consent.requireGiven);
  };
});
