import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_consent_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Sends [prompt] to Groq's web-search model and returns its reply.
typedef AskGroq = Future<String> Function(String prompt);

/// Fixes a script with Groq's web-search model and the user's key
/// (spec FR-19). Saving is left to the caller, which can still cancel.
class GroqScriptFixService {
  const GroqScriptFixService({required this.askGroq});

  final AskGroq askGroq;

  /// Throws [TooManyLinesForAiException] above [mostLinesForGroq] lines,
  /// before anything is sent, and [NoScriptRowsException] when the reply
  /// has no rows.
  Future<CorrectedScript> fix({
    required SourceVideo video,
    required Transcript transcript,
    required LineSelection selection,
  }) async {
    final lines = linesToCheck(
      transcript,
      selection,
      mostLines: mostLinesForGroq,
    );
    final reply = await askGroq(
      scriptPromptFor(videoTitle: video.title, lines: lines),
    );
    return applyCorrectedScript(transcript, reply);
  }
}

final groqScriptFixServiceProvider = Provider<GroqScriptFixService>((ref) {
  final keys = ref.watch(groqKeyStoreProvider);
  final consent = ref.watch(groqConsentStoreProvider);
  return GroqScriptFixService(
    askGroq: (prompt) async => GroqClient(
      apiKey: await keys.savedKey(),
      beforeUpload: consent.requireGiven,
    ).fixScript(prompt),
  );
});
