import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/lyrics/data/lrclib_client.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// A stand-in for lrclib.net: answers every request with [status] and [body],
/// and remembers the last request's URI.
class FakeLrclib {
  FakeLrclib(this.status, this.body);

  final int status;
  final String body;
  late final HttpServer server;
  Uri? lastRequest;

  Future<LrclibClient> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      lastRequest = request.uri;
      request.response
        ..statusCode = status
        ..write(body);
      await request.response.close();
    });
    return LrclibClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/api'),
    );
  }
}

const reply = '''
[
  {"trackName": "Song", "duration": 214.4, "instrumental": false,
   "syncedLyrics": "[00:01.00] Words", "plainLyrics": "Words"},
  {"trackName": "Plain only", "duration": 200.0, "instrumental": false,
   "syncedLyrics": null, "plainLyrics": "Words"},
  {"trackName": "Beat", "duration": 100.0, "instrumental": true,
   "syncedLyrics": null, "plainLyrics": null}
]
''';

void main() {
  test('search_reads_songs_and_skips_instrumentals', () async {
    final client = await FakeLrclib(200, reply).start();

    final songs = await client.search('Song');

    expect(
      songs.map((song) => (song.trackName, song.length, song.syncedLyrics)),
      [
        ('Song', const Duration(milliseconds: 214400), '[00:01.00] Words'),
        ('Plain only', const Duration(seconds: 200), ''),
      ],
    );
  });

  test('search_sends_the_query_text', () async {
    final server = FakeLrclib(200, '[]');
    final client = await server.start();

    await client.search('Never Gonna');

    expect(server.lastRequest!.queryParameters, {'q': 'Never Gonna'});
  });

  test('search_maps_a_failed_reply_to_offline', () async {
    final client = await FakeLrclib(503, 'down').start();

    await expectLater(client.search('x'), throwsA(isA<OfflineException>()));
  });

  test('search_maps_a_refused_connection_to_offline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = LrclibClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/api'),
    );
    await server.close(force: true);

    await expectLater(client.search('x'), throwsA(isA<OfflineException>()));
  });

  test('search_rejects_a_reply_that_is_not_a_list', () async {
    final client = await FakeLrclib(200, jsonEncode({'oops': 1})).start();

    await expectLater(client.search('x'), throwsFormatException);
  });
}
