/// The linked video is longer than links may be (spec FR-36, §8): 3 hours
/// with captions, 2 without.
class LinkTooLongException implements Exception {
  const LinkTooLongException(this.length);

  final Duration length;

  @override
  String toString() => 'LinkTooLongException: $length';
}

/// Groq found nothing about the topic, or nothing long enough (spec FR-36).
class NoMomentsFoundException implements Exception {
  const NoMomentsFoundException();

  @override
  String toString() => 'NoMomentsFoundException';
}

/// Groq asked to wait so long that the day's free allowance must be used
/// up (spec FR-36, §8).
class GroqDailyLimitException implements Exception {
  const GroqDailyLimitException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'GroqDailyLimitException: $retryAfter';
}
