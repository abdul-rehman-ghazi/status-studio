import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/lyrics/application/lyrics_service.dart';
import 'package:status_studio/src/features/lyrics/data/lrclib_client.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const video = SourceVideo(
  videoId: 'dQw4w9WgXcQ',
  title: 'Rick Astley - Never Gonna Give You Up (Official Video)',
  channel: 'Rick Astley',
  duration: Duration(seconds: 213),
);

const key = TranscriptKey(
  videoId: 'dQw4w9WgXcQ',
  language: ScriptLanguage.auto,
);

const matchingReply = '''
[{"trackName": "Never Gonna Give You Up", "duration": 214.0, "instrumental": false,
  "syncedLyrics": "[00:18.90] We're no strangers to love\\n[00:22.61] You know the rules"}]
''';

const otherSongReply = '''
[{"trackName": "Something Else", "duration": 214.0, "instrumental": false,
  "syncedLyrics": "[00:01.00] x"}]
''';

void main() {
  late Directory folder;
  late TranscriptStore store;
  late HttpServer server;
  late String reply;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('lyrics_service_test');
    store = TranscriptStore(folder, clock: DateTime.now);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    reply = matchingReply;
    server.listen((request) async {
      request.response.write(reply);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await folder.delete(recursive: true);
  });

  LyricsService service({DateTime Function()? clock}) => LyricsService(
    client: LrclibClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/api'),
    ),
    store: Future.value(store),
    clock: clock,
  );

  test('replace_script_returns_the_lyrics_as_script_lines', () async {
    final transcript = await service().replaceScript(
      video,
      ScriptLanguage.auto,
    );

    expect(transcript.lines.map((line) => line.text), [
      "We're no strangers to love",
      'You know the rules',
    ]);
  });

  test('replace_script_saves_lyrics_as_the_newest_script', () async {
    await store.save(
      key,
      SavedTranscript(
        transcript: const Transcript(languageCode: 'en', lines: []),
        source: groqSource,
        savedAt: DateTime(2026),
      ),
    );

    await service(clock: () => DateTime(2026, 6))
        .replaceScript(video, ScriptLanguage.auto);

    expect((await store.load(key)).source, lyricsSource);
  });

  test('replace_script_names_the_language_from_the_lyrics', () async {
    final transcript = await service().replaceScript(
      video,
      ScriptLanguage.auto,
    );

    expect(transcript.languageCode, 'en');
  });

  test('replace_script_throws_when_no_song_matches', () async {
    reply = otherSongReply;

    await expectLater(
      service().replaceScript(video, ScriptLanguage.auto),
      throwsA(isA<LyricsNotFoundException>()),
    );
  });
}
