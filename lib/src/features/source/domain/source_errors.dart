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

/// A download stream ended before all its bytes arrived. Treated as a
/// network failure, since that is what usually cuts a stream short.
class IncompleteDownloadException extends OfflineException {
  const IncompleteDownloadException(super.reason);

  @override
  String toString() => 'IncompleteDownloadException: $reason';
}

/// The server sent the whole file instead of the requested byte range, so
/// a partial download isn't possible from it.
class RangeNotSupportedException implements Exception {
  const RangeNotSupportedException(this.reason);

  final String reason;

  @override
  String toString() => 'RangeNotSupportedException: $reason';
}

/// YouTube refused a stream URL (HTTP 403), usually because it expired.
class ExpiredStreamUrlException implements Exception {
  const ExpiredStreamUrlException(this.reason);

  final String reason;

  @override
  String toString() => 'ExpiredStreamUrlException: $reason';
}

/// A stream request failed for a reason a retry may fix (5xx, 429, …).
/// Shown like being offline, which offers Retry (spec §8).
class StreamRequestFailedException extends OfflineException {
  const StreamRequestFailedException(super.reason);

  @override
  String toString() => 'StreamRequestFailedException: $reason';
}

/// YouTube answered in a way yt-dlp couldn't read, even after updating:
/// usually a YouTube change that a later yt-dlp will handle (spec §8).
class YouTubeChangedException implements Exception {
  const YouTubeChangedException(this.reason);

  final String reason;

  @override
  String toString() => 'YouTubeChangedException: $reason';
}

/// The video file is missing, can't be read, isn't a valid video, or has no
/// audio track, so it can't be fingerprinted or used (spec FR-1, §8).
class VideoUnreadableException implements Exception {
  const VideoUnreadableException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoUnreadableException: $reason';
}

/// The phone can't say how much space is free, so a copy can't be checked
/// first (spec FR-1). It is not the same as being out of space.
class StorageUnknownException implements Exception {
  const StorageUnknownException(this.reason);

  final String reason;

  @override
  String toString() => 'StorageUnknownException: $reason';
}

/// The system gallery picker failed or is busy (for example already open),
/// as opposed to the user closing it (spec FR-1).
class VideoPickFailedException implements Exception {
  const VideoPickFailedException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoPickFailedException: $reason';
}
