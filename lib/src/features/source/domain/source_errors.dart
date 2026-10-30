/// The video is private, age-restricted, removed or otherwise can't be
/// downloaded (spec §8).
class VideoUnavailableException implements Exception {
  const VideoUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoUnavailableException: $reason';
}

/// The network dropped during a download (spec §8).
class OfflineException implements Exception {
  const OfflineException(this.reason);

  final String reason;

  @override
  String toString() => 'OfflineException: $reason';
}

/// The phone ran out of space during a download or export (spec §8).
class InsufficientStorageException implements Exception {
  const InsufficientStorageException(this.reason);

  final String reason;

  @override
  String toString() => 'InsufficientStorageException: $reason';
}
