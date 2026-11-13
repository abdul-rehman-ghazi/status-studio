/// The linked video is longer than links may be (spec FR-36, §8): 3 hours
/// with captions, 2 without.
class LinkTooLongException implements Exception {
  const LinkTooLongException(this.length);

  final Duration length;

  @override
  String toString() => 'LinkTooLongException: $length';
}
