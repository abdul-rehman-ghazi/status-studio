/// No face was found often enough to follow (spec FR-23, §8). The crop is
/// left as it was.
class NoSubjectFoundException implements Exception {
  const NoSubjectFoundException();

  @override
  String toString() => 'NoSubjectFoundException';
}

/// Frames, decoding or the detector failed (spec FR-23, §8).
class FollowFailedException implements Exception {
  const FollowFailedException(this.reason);

  final String reason;

  @override
  String toString() => 'FollowFailedException: $reason';
}
