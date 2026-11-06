/// Frames, decoding or the detector failed (spec FR-23, §8).
class FollowFailedException implements Exception {
  const FollowFailedException(this.reason);

  final String reason;

  @override
  String toString() => 'FollowFailedException: $reason';
}
