import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

typedef _Reply = ({int status, String body, Map<String, String> headers});

_Reply _ok(String body) => (status: 200, body: body, headers: const {});
_Reply _status(int status, [Map<String, String> headers = const {}]) =>
    (status: status, body: '', headers: headers);

const _verbose =
    '{"segments":[{"start":1.5,"end":3.0,"text":" Hello","no_speech_prob":0.1}]}';

void main() {
  late HttpServer server;
  late List<_Reply> replies;
  late List<HttpRequest> seen;
  late List<String> bodies;
  late List<Duration> waits;
  late File piece;

  setUp(() async {
    replies = [];
    seen = [];
    bodies = [];
    waits = [];
    piece = File('${Directory.systemTemp.path}/groq_piece_test.m4a')
      ..writeAsBytesSync([1, 2, 3]);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request);
      bodies.add(
        latin1.decode(await request.fold<List<int>>([], (a, b) => a + b)),
      );
      final reply = replies.removeAt(0);
      request.response.statusCode = reply.status;
      reply.headers.forEach(request.response.headers.set);
      request.response.write(reply.body);
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  GroqClient client() => GroqClient(
    apiKey: 'gsk_secret',
    baseUri: Uri.parse('http://127.0.0.1:${server.port}/openai/v1'),
    wait: (duration) async => waits.add(duration),
  );

  test('check_key_sends_the_key_as_a_bearer_token_to_models', () async {
    replies = [_ok('{}')];

    await client().checkKey();

    expect(seen.single.uri.path, '/openai/v1/models');
    expect(seen.single.headers.value('authorization'), 'Bearer gsk_secret');
  });

  test('check_key_throws_key_rejected_on_401', () async {
    replies = [_status(401)];

    expect(client().checkKey(), throwsA(isA<GroqKeyRejectedException>()));
  });

  test(
    'transcribe_returns_segments_with_times_and_no_speech_probability',
    () async {
      replies = [_ok(_verbose)];

      final segments = await client().transcribe(piece, languageCode: 'ur');

      expect(segments.single.from, const Duration(milliseconds: 1500));
      expect(segments.single.text, ' Hello');
      expect(segments.single.noSpeechProbability, 0.1);
    },
  );

  test('transcribe_sends_the_language_when_one_is_chosen', () async {
    replies = [_ok(_verbose)];

    await client().transcribe(piece, languageCode: 'ur');

    expect(bodies.single, contains('name="language"\r\n\r\nur'));
  });

  test('transcribe_omits_the_language_for_automatic_detection', () async {
    replies = [_ok(_verbose)];

    await client().transcribe(piece, languageCode: null);

    expect(bodies.single, isNot(contains('name="language"')));
  });

  test('transcribe_waits_and_resends_after_a_short_429', () async {
    replies = [
      _status(429, {'retry-after': '7'}),
      _ok(_verbose),
    ];

    await client().transcribe(piece, languageCode: null);

    expect(waits, [const Duration(seconds: 7)]);
    expect(seen, hasLength(2));
  });

  test(
    'transcribe_throws_rate_limited_when_the_wait_exceeds_a_minute',
    () async {
      replies = [
        _status(429, {'retry-after': '120'}),
      ];

      expect(
        client().transcribe(piece, languageCode: null),
        throwsA(
          isA<GroqRateLimitedException>().having(
            (error) => error.retryAfter,
            'retryAfter',
            const Duration(minutes: 2),
          ),
        ),
      );
    },
  );

  test('transcribe_retries_a_server_error_once', () async {
    replies = [_status(503), _ok(_verbose)];

    final segments = await client().transcribe(piece, languageCode: null);

    expect(segments, hasLength(1));
  });

  test('transcribe_fails_after_two_server_errors', () async {
    replies = [_status(503), _status(503)];

    expect(
      client().transcribe(piece, languageCode: null),
      throwsA(isA<GroqFailedException>()),
    );
  });

  test('transcribe_throws_offline_when_groq_is_unreachable', () async {
    final unreachable = GroqClient(
      apiKey: 'gsk_secret',
      baseUri: Uri.parse('http://127.0.0.1:1/openai/v1'),
    );

    expect(
      unreachable.transcribe(piece, languageCode: null),
      throwsA(isA<GroqOfflineException>()),
    );
  });

  test('errors_never_contain_the_key', () async {
    replies = [_status(500), _status(500)];

    final error = await client()
        .transcribe(piece, languageCode: null)
        .then<Object>((_) => '', onError: (Object e) => e);

    expect(error.toString(), isNot(contains('gsk_secret')));
  });

  group('fix_script', () {
    const chatReply =
        '{"choices":[{"message":{"role":"assistant","content":"1 | a | b | ok"}}]}';

    test('sends_the_prompt_to_the_web_search_model_with_the_key', () async {
      replies = [_ok(chatReply)];

      await client().fixScript('fix these rows');

      final sent = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(seen.single.uri.path, '/openai/v1/chat/completions');
      expect(seen.single.headers.value('authorization'), 'Bearer gsk_secret');
      expect(sent['model'], 'openai/gpt-oss-120b');
      expect(sent['tools'], [
        {'type': 'browser_search'},
      ]);
      expect((sent['messages'] as List).single, {
        'role': 'user',
        'content': 'fix these rows',
      });
    });

    test('returns_the_text_of_the_reply', () async {
      replies = [_ok(chatReply)];

      final text = await client().fixScript('fix these rows');

      expect(text, '1 | a | b | ok');
    });

    test('waits_out_a_short_rate_limit_and_asks_again', () async {
      replies = [
        _status(429, {'retry-after': '2'}),
        _ok(chatReply),
      ];

      final text = await client().fixScript('fix these rows');

      expect(text, '1 | a | b | ok');
      expect(waits, [const Duration(seconds: 2)]);
    });

    test('throws_key_rejected_on_401', () async {
      replies = [_status(401)];

      expect(
        client().fixScript('fix these rows'),
        throwsA(isA<GroqKeyRejectedException>()),
      );
    });
  });
}
