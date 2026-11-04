import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';

const _timeout = Duration(seconds: 20);

/// The one place that talks to `lrclib.net`, a free lyrics service that
/// needs no key (spec FR-17). Only the video's cleaned title leaves the
/// phone.
class LrclibClient {
  LrclibClient({Uri? baseUri, HttpClient? httpClient})
    : _baseUri = baseUri ?? Uri.parse('https://lrclib.net/api'),
      _http = httpClient ?? HttpClient();

  final Uri _baseUri;
  final HttpClient _http;

  /// Songs matching [query], best match first. Throws `OfflineException`
  /// when LRCLIB can't be reached.
  Future<List<LyricsCandidate>> search(String query) {
    return guardIo(() async {
      final uri = Uri.parse('$_baseUri/search')
          .replace(queryParameters: {'q': query});
      final request = await _http.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'StatusStudio/1.0');
      final reply = await request.close().timeout(_timeout);
      final body = await reply.transform(utf8.decoder).join().timeout(_timeout);
      if (reply.statusCode != HttpStatus.ok) {
        throw HttpException('lrclib.net answered ${reply.statusCode}.');
      }
      return _candidatesIn(jsonDecode(body));
    });
  }
}

List<LyricsCandidate> _candidatesIn(Object? json) {
  if (json is! List) {
    throw const FormatException('LRCLIB did not send a list.');
  }
  return [
    for (final entry in json)
      if (entry case {
        'trackName': final String trackName,
        'duration': final num seconds,
        'instrumental': false,
      })
        LyricsCandidate(
          trackName: trackName,
          length: Duration(milliseconds: (seconds * 1000).round()),
          syncedLyrics: _syncedLyricsOf(entry),
        ),
  ];
}

String _syncedLyricsOf(Map<Object?, Object?> entry) =>
    entry['syncedLyrics'] is String ? entry['syncedLyrics']! as String : '';
