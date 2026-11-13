/// Groq refused the API key (401 or 403); spec §8.
class GroqKeyRejectedException implements Exception {
  const GroqKeyRejectedException();

  @override
  String toString() => 'GroqKeyRejectedException';
}

/// Groq's rate limit is hit and the wait is longer than the app will
/// sit through; spec §8.
class GroqRateLimitedException implements Exception {
  const GroqRateLimitedException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'GroqRateLimitedException: retry in $retryAfter';
}

/// Groq failed in some other way, or twice on a 5xx or 498.
class GroqFailedException implements Exception {
  const GroqFailedException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'GroqFailedException: HTTP $statusCode';
}

/// The phone couldn't reach Groq.
class GroqOfflineException implements Exception {
  const GroqOfflineException();

  @override
  String toString() => 'GroqOfflineException';
}

/// Groq was asked for without a saved key.
class NoGroqKeyException implements Exception {
  const NoGroqKeyException();

  @override
  String toString() => 'NoGroqKeyException';
}

/// Groq's chat reply wasn't the JSON asked for (spec FR-36).
class GroqUnreadableReplyException implements Exception {
  const GroqUnreadableReplyException(this.reason);

  final String reason;

  @override
  String toString() => 'GroqUnreadableReplyException: $reason';
}

/// The user hasn't agreed to send audio or lines to Groq (spec FR-30).
/// Thrown before anything is sent.
class NoGroqConsentException implements Exception {
  const NoGroqConsentException();

  @override
  String toString() => 'NoGroqConsentException';
}

/// Groq's translation of the lyrics didn't come back line for line (spec
/// FR-37, §8).
class LyricsNotTranslatedException implements Exception {
  const LyricsNotTranslatedException(this.reason);

  final String reason;

  @override
  String toString() => 'LyricsNotTranslatedException: $reason';
}
