import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

const _longestWait = Duration(seconds: 60);
const _defaultWait = Duration(seconds: 5);
const _model = 'whisper-large-v3-turbo';

// The only Groq model the key can call that searches the web (spec §10 #6).
const _scriptFixModel = 'openai/gpt-oss-120b';

/// One stretch of speech Groq reports for a piece, timed within the piece.
class GroqSegment {
  const GroqSegment({
    required this.from,
    required this.to,
    required this.text,
    required this.noSpeechProbability,
  });

  final Duration from;
  final Duration to;
  final String text;
  final double noSpeechProbability;
}

/// The one place that talks to `api.groq.com` (spec FR-12a). The key goes
/// only into the Authorization header, never into a log or an error.
class GroqClient {
  GroqClient({
    required this.apiKey,
    Uri? baseUri,
    HttpClient? httpClient,
    Future<void> Function(Duration)? wait,
  }) : _baseUri = baseUri ?? Uri.parse('https://api.groq.com/openai/v1'),
       _http = httpClient ?? HttpClient(),
       _wait = wait ?? Future<void>.delayed;

  final String apiKey;
  final Uri _baseUri;
  final HttpClient _http;
  final Future<void> Function(Duration) _wait;

  /// Throws [GroqKeyRejectedException] unless Groq accepts the key. Free,
  /// and sends no audio.
  Future<void> checkKey() async {
    await _send(() => _open('GET', '/models'));
  }

  /// Writes one FLAC piece, in [languageCode] or, when it's `null`,
  /// in the language Groq detects.
  Future<List<GroqSegment>> transcribe(
    File piece, {
    required String? languageCode,
  }) async {
    final audio = await piece.readAsBytes();
    final boundary = 'studio${DateTime.now().microsecondsSinceEpoch}';
    final body = _multipartBody(boundary, audio, languageCode);
    final reply = await _send(() async {
      final request = await _open('POST', '/audio/transcriptions');
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      request.add(body);
      return request;
    });
    return _segmentsOf(reply);
  }

  /// The reply of Groq's web-search model to [prompt] (spec FR-19). Empty
  /// when the model answers with no text.
  Future<String> fixScript(String prompt) async {
    final body = utf8.encode(
      jsonEncode({
        'model': _scriptFixModel,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'tools': [
          {'type': 'browser_search'},
        ],
        'tool_choice': 'auto',
      }),
    );
    final reply = await _send(() async {
      final request = await _open('POST', '/chat/completions');
      request.headers.contentType = ContentType.json;
      request.add(body);
      return request;
    });
    return _replyTextOf(reply);
  }

  Future<HttpClientRequest> _open(String method, String path) async {
    final request = await _http.openUrl(
      method,
      _baseUri.replace(path: '${_baseUri.path}$path'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    return request;
  }

  /// Sends the request [open] builds, waiting out short rate limits and
  /// retrying a server error once; returns the body of a 200.
  Future<String> _send(Future<HttpClientRequest> Function() open) async {
    var serverErrors = 0;
    for (var attempt = 0; ; attempt++) {
      final response = await _respond(open);
      final status = response.statusCode;
      if (status == HttpStatus.ok) {
        return utf8.decodeStream(response);
      }
      await response.drain<void>();
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        throw const GroqKeyRejectedException();
      }
      if (status == HttpStatus.tooManyRequests) {
        final wait = _retryAfter(response);
        if (wait > _longestWait || attempt >= 3) {
          throw GroqRateLimitedException(wait);
        }
        await _wait(wait);
        continue;
      }
      final retryable = status >= 500 || status == 498;
      if (!retryable || ++serverErrors > 1) {
        throw GroqFailedException(status);
      }
    }
  }

  Future<HttpClientResponse> _respond(
    Future<HttpClientRequest> Function() open,
  ) async {
    try {
      final request = await open();
      return await request.close();
    } on SocketException {
      throw const GroqOfflineException();
    } on HandshakeException {
      throw const GroqOfflineException();
    }
  }

  Duration _retryAfter(HttpClientResponse response) {
    final seconds = num.tryParse(response.headers.value('retry-after') ?? '');
    return seconds == null
        ? _defaultWait
        : Duration(milliseconds: (seconds * 1000).round());
  }

  List<int> _multipartBody(
    String boundary,
    List<int> audio,
    String? languageCode,
  ) {
    final fields = {
      'model': _model,
      'response_format': 'verbose_json',
      'timestamp_granularities[]': 'segment',
      'temperature': '0',
      ?(languageCode == null ? null : 'language'): languageCode,
    };
    final bytes = BytesBuilder();
    for (final MapEntry(:key, :value) in fields.entries) {
      bytes.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="$key"'
          '\r\n\r\n$value\r\n',
        ),
      );
    }
    bytes
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="file"; '
          'filename="piece.flac"\r\nContent-Type: audio/flac\r\n\r\n',
        ),
      )
      ..add(audio)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    return bytes.takeBytes();
  }

  String _replyTextOf(String reply) {
    final decoded = jsonDecode(reply) as Map<String, dynamic>;
    final choices = (decoded['choices'] as List<dynamic>?) ?? const [];
    if (choices.isEmpty) {
      return '';
    }
    final message = (choices.first as Map<String, dynamic>)['message'];
    return ((message as Map<String, dynamic>)['content'] as String?) ?? '';
  }

  List<GroqSegment> _segmentsOf(String reply) {
    final decoded = jsonDecode(reply) as Map<String, dynamic>;
    final segments = (decoded['segments'] as List<dynamic>?) ?? const [];
    return [
      for (final segment in segments.cast<Map<String, dynamic>>())
        GroqSegment(
          from: _seconds(segment['start']),
          to: _seconds(segment['end']),
          text: segment['text'] as String,
          noSpeechProbability: (segment['no_speech_prob'] as num).toDouble(),
        ),
    ];
  }

  Duration _seconds(Object? value) =>
      Duration(milliseconds: ((value! as num) * 1000).round());
}
