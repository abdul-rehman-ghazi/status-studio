/// The speech model couldn't be downloaded (spec §8).
class ModelDownloadException implements Exception {
  const ModelDownloadException(this.reason);

  final String reason;

  @override
  String toString() => 'ModelDownloadException: $reason';
}

/// Whisper failed on a chunk of audio.
class TranscriptionFailedException implements Exception {
  const TranscriptionFailedException(this.reason);

  final String reason;

  @override
  String toString() => 'TranscriptionFailedException: $reason';
}

/// The whole video produced no lines of speech (spec §8).
class NoSpeechFoundException implements Exception {
  const NoSpeechFoundException();

  @override
  String toString() => 'NoSpeechFoundException';
}

/// YouTube has no caption track to use for the chosen language.
class NoCaptionTrackException implements Exception {
  const NoCaptionTrackException();

  @override
  String toString() => 'NoCaptionTrackException';
}

/// No saved script (or saved partial progress) exists for a key, or the
/// file is unreadable.
class NoSavedTranscriptException implements Exception {
  const NoSavedTranscriptException();

  @override
  String toString() => 'NoSavedTranscriptException';
}
