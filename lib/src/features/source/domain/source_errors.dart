/// The video is private, age-restricted, removed or otherwise can't be
/// downloaded (spec §8, FR-35).
class VideoUnavailableException implements Exception {
  const VideoUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoUnavailableException: $reason';
}

/// The site answered in a way yt-dlp couldn't read: usually a site change
/// that a newer yt-dlp handles (spec §8, FR-35, FR-50).
class SiteChangedException implements Exception {
  const SiteChangedException(this.reason);

  final String reason;

  @override
  String toString() => 'SiteChangedException: $reason';
}

/// yt-dlp has no reader for the link's site (spec §8, FR-50).
class UnsupportedSiteException implements Exception {
  const UnsupportedSiteException(this.reason);

  final String reason;

  @override
  String toString() => 'UnsupportedSiteException: $reason';
}

/// The site shows the video only to a signed-in user; the app takes no
/// cookies or accounts (spec §8, FR-50).
class LoginRequiredException implements Exception {
  const LoginRequiredException(this.reason);

  final String reason;

  @override
  String toString() => 'LoginRequiredException: $reason';
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

/// The video file is missing, can't be read, isn't a valid video, or has no
/// audio track, so it can't be fingerprinted or used (spec FR-1, §8).
class VideoUnreadableException implements Exception {
  const VideoUnreadableException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoUnreadableException: $reason';
}

/// The kept copy of a video was cleaned up or deleted, so the user must
/// choose the video again (spec FR-1, §8).
class KeptVideoMissingException implements Exception {
  const KeptVideoMissingException(this.videoId);

  final String videoId;

  @override
  String toString() => 'KeptVideoMissingException: $videoId';
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

/// An AV1 video, which the bundled FFmpeg can't decode, couldn't be converted
/// to H.264 on this phone (spec FR-1, §8, M31).
class VideoNotConvertibleException implements Exception {
  const VideoNotConvertibleException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoNotConvertibleException: $reason';
}
