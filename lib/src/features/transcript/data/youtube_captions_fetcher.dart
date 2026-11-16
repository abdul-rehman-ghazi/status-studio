import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/youtube_captions.dart';

/// Fetches a YouTube caption track as lines (spec FR-36).
class YouTubeCaptionsFetcher {
  YouTubeCaptionsFetcher({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient();

  final HttpClient _http;

  /// Throws [OfflineException] without a network, and
  /// [SiteChangedException] when YouTube doesn't hand the track over.
  Future<List<TranscriptLine>> fetch(String json3Url) => guardIo(() async {
    final request = await _http.getUrl(Uri.parse(json3Url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw SiteChangedException('Captions answered ${response.statusCode}.');
    }
    final body = await utf8.decodeStream(response);
    final json = jsonDecode(body) as Map<String, Object?>;
    return linesFromCaptions(captionsFromJson3(json));
  });
}

final youTubeCaptionsFetcherProvider = Provider<YouTubeCaptionsFetcher>(
  (ref) => YouTubeCaptionsFetcher(),
);
