class InvalidLinkException implements Exception {
  const InvalidLinkException(this.link);

  final String link;

  @override
  String toString() => 'InvalidLinkException: $link';
}

const _youtubeHosts = {'youtube.com', 'www.youtube.com', 'm.youtube.com'};
const _shortLinkHost = 'youtu.be';
const _pathIdPrefixes = {'shorts', 'live'};
final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _whitespace = RegExp(r'\s');

/// The page yt-dlp reads for a pasted or shared link (spec FR-50), or throws
/// [InvalidLinkException]. A YouTube link becomes the watch page of its ID,
/// so a playlist or start time in it never reaches yt-dlp; any other link
/// goes as pasted, with `https://` added when it has no scheme.
String parseVideoLink(String link) {
  final uri = _webUriOf(link);
  if (_isYouTubeHost(uri.host)) {
    return youTubeWatchUrl(parseYouTubeVideoId(link));
  }
  return uri.toString();
}

/// Whether [videoKey] is a YouTube ID rather than another site's key
/// (spec FR-50).
bool isYouTubeVideoKey(String videoKey) => _videoIdPattern.hasMatch(videoKey);

/// A YouTube page, as yt-dlp reads it.
String youTubeWatchUrl(String videoId) =>
    'https://www.youtube.com/watch?v=$videoId';

/// Extracts the 11-character video ID from any YouTube link form in spec
/// FR-1, or throws [InvalidLinkException].
String parseYouTubeVideoId(String link) {
  final uri = Uri.tryParse(_withScheme(link.trim()));
  final candidate = uri == null ? null : _idFromUri(uri);
  if (candidate == null || !_videoIdPattern.hasMatch(candidate)) {
    throw InvalidLinkException(link);
  }
  return candidate;
}

/// An `http` or `https` link whose host has a dot, so a typed word isn't
/// sent to yt-dlp as a site (*Claude's call*, FR-50).
Uri _webUriOf(String link) {
  final trimmed = link.trim();
  final uri = _whitespace.hasMatch(trimmed)
      ? null
      : Uri.tryParse(_withScheme(trimmed));
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      !uri.host.contains('.')) {
    throw InvalidLinkException(link);
  }
  return uri;
}

bool _isYouTubeHost(String host) {
  final lowerHost = host.toLowerCase();
  return lowerHost == _shortLinkHost || _youtubeHosts.contains(lowerHost);
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
