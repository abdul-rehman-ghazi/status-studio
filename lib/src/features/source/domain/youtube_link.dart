class InvalidYouTubeLinkException implements Exception {
  const InvalidYouTubeLinkException(this.link);

  final String link;

  @override
  String toString() => 'InvalidYouTubeLinkException: $link';
}

const _youtubeHosts = {'youtube.com', 'www.youtube.com', 'm.youtube.com'};
const _shortLinkHost = 'youtu.be';
const _pathIdPrefixes = {'shorts', 'live'};
final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Extracts the 11-character video ID from any YouTube link form in spec
/// FR-1, or throws [InvalidYouTubeLinkException].
String parseYouTubeVideoId(String link) {
  final uri = Uri.tryParse(_withScheme(link.trim()));
  final candidate = uri == null ? null : _idFromUri(uri);
  if (candidate == null || !_videoIdPattern.hasMatch(candidate)) {
    throw InvalidYouTubeLinkException(link);
  }
  return candidate;
}

String _withScheme(String link) =>
    link.contains('://') ? link : 'https://$link';

/// The ID-shaped part of the link, if the link has one; validated by the caller.
String? _idFromUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  if (host == _shortLinkHost) {
    return segments.firstOrNull;
  }
  if (!_youtubeHosts.contains(host) || segments.isEmpty) {
    return null;
  }
  if (segments.first == 'watch') {
    return uri.queryParameters['v'];
  }
  if (segments.length >= 2 && _pathIdPrefixes.contains(segments.first)) {
    return segments[1];
  }
  return null;
}
