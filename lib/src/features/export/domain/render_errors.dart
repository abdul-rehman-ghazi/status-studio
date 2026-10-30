/// The render didn't produce a reel (spec §8: "Couldn't make the reel.").
class RenderFailedException implements Exception {
  const RenderFailedException(this.reason);

  final String reason;

  @override
  String toString() => 'RenderFailedException: $reason';
}
