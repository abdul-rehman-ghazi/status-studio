import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Counts the audio a Groq run would send for a key.
typedef AudioStillToSend = Future<Duration> Function(
  TranscriptStore store,
  TranscriptKey key,
  Duration videoLength,
);

/// How much audio Get still sends to Groq for [key] (spec FR-45): none
/// for a saved script, else [videoLength] less the pieces a partial run
/// already wrote.
Future<Duration> audioStillToSend(
  TranscriptStore store,
  TranscriptKey key,
  Duration videoLength,
) async {
  if (await _isSaved(store, key)) {
    return Duration.zero;
  }
  return audioStillToSendAgain(store, key, videoLength);
}

/// Writing again resumes a partial run too, so only the saved script is
/// left out.
Future<Duration> audioStillToSendAgain(
  TranscriptStore store,
  TranscriptKey key,
  Duration videoLength,
) async {
  final written = transcriptionChunk * await _writtenPieces(store, key);
  return written >= videoLength ? Duration.zero : videoLength - written;
}

Future<bool> _isSaved(TranscriptStore store, TranscriptKey key) async {
  try {
    await store.load(key);
    return true;
  } on NoSavedTranscriptException {
    return false;
  }
}

Future<int> _writtenPieces(TranscriptStore store, TranscriptKey key) async {
  try {
    final partial = await store.loadPartial(key, groqSource);
    return partial.completedChunks;
  } on NoSavedTranscriptException {
    return 0;
  }
}
