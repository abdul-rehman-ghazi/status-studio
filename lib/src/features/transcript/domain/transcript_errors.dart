/// The whole video produced no lines of speech (spec §8).
class NoSpeechFoundException implements Exception {
  const NoSpeechFoundException();

  @override
  String toString() => 'NoSpeechFoundException';
}

/// No saved script (or saved partial progress) exists for a key, or the
/// file is unreadable.
class NoSavedTranscriptException implements Exception {
  const NoSavedTranscriptException();

  @override
  String toString() => 'NoSavedTranscriptException';
}

/// No video details were kept for a video id, or the file is unreadable.
class NoSavedVideoException implements Exception {
  const NoSavedVideoException();

  @override
  String toString() => 'NoSavedVideoException';
}
