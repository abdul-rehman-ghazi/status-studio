import 'package:status_studio/src/features/source/domain/source_errors.dart';

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
/// Shown like being offline, which offers Try again (spec §8).
class StreamRequestFailedException extends OfflineException {
  const StreamRequestFailedException(super.reason);

  @override
  String toString() => 'StreamRequestFailedException: $reason';
}

/// The video has no MP4 stream with a segment index, so its cuts can't be
/// fetched on their own (spec FR-37, §8). The whole video is never
/// downloaded instead.
class NotDownloadableInPartsException implements Exception {
  const NotDownloadableInPartsException(this.reason);

  final String reason;

  @override
  String toString() => 'NotDownloadableInPartsException: $reason';
}

/// The user tapped Cancel while the cuts were downloading (spec FR-37).
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'DownloadCancelledException';
}

/// Media3 couldn't join the cuts (spec FR-37, §8).
class JoinFailedException implements Exception {
  const JoinFailedException(this.reason);

  final String reason;

  @override
  String toString() => 'JoinFailedException: $reason';
}
