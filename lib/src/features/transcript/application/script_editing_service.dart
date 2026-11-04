import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Keeps a corrected script, so the video opens with it next time (FR-18).
class ScriptEditingService {
  ScriptEditingService({required this.store, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<TranscriptStore> store;
  final DateTime Function() _clock;

  /// Saved as the newest script for [video] and [language], so it is the one
  /// that reopens (FR-14).
  Future<void> saveCorrected(
    SourceVideo video,
    ScriptLanguage language,
    Transcript corrected,
  ) async {
    await (await store).save(
      TranscriptKey(videoId: video.videoId, language: language),
      SavedTranscript(
        transcript: corrected,
        source: editedSource,
        savedAt: _clock(),
      ),
    );
  }
}

final scriptEditingServiceProvider = Provider<ScriptEditingService>(
  (ref) =>
      ScriptEditingService(store: ref.watch(transcriptStoreProvider.future)),
);
