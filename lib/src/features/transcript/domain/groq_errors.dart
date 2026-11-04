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
