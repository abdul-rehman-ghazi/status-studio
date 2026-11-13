import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:status_studio/src/features/transcript/domain/groq_allowance.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

const _longestWait = Duration(seconds: 60);
const _defaultWait = Duration(seconds: 5);
const _audioLimitHeader = 'x-ratelimit-limit-audio-seconds';
const _audioRemainingHeader = 'x-ratelimit-remaining-audio-seconds';
const _audioResetHeader = 'x-ratelimit-reset-audio-seconds';

/// The model every script is written with (spec FR-12a).
const scriptModel = 'whisper-large-v3';

/// Segments Groq is this sure hold no speech are dropped. Turbo always
/// reported 0 (§10 Q5); large-v3 reports real values (0.00 to 0.12 on the
/// reference clip), so the cutoff is live since M24. Here, not in the
/// transcriber, so tool/voice_check.dart can apply the same rule.
const groqNoSpeechCutoff = 0.6;

/// A chat request whose reply must be one JSON object (spec FR-36).
class GroqChatRequest {
  const GroqChatRequest({
    required this.model,
    required this.instructions,
    required this.message,
  });

  final String model;

  /// The system message: what to do and the reply's shape.
  final String instructions;

  /// The user message: the transcript part or the candidates.
  final String message;
}

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
    required this.beforeUpload,
    this.model = scriptModel,
    this.onAllowance,
    Uri? baseUri,
    HttpClient? httpClient,
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _baseUri = baseUri ?? Uri.parse('https://api.groq.com/openai/v1'),
       _http = httpClient ?? HttpClient(),
       _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final String apiKey;

  /// Runs before anything of the user's is sent, and throws to stop it: the
  /// app passes the consent check (spec FR-30). [checkKey] sends nothing of
  /// theirs, so it doesn't call this.
  final Future<void> Function() beforeUpload;

  /// Only tool/voice_check.dart passes another model, to compare them.
  final String model;

  /// Told the audio allowance each reply reports (spec FR-45).
  final void Function(GroqAllowance)? onAllowance;
  final Uri _baseUri;
  final HttpClient _http;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  /// Throws [GroqKeyRejectedException] unless Groq accepts the key. Free,
  /// and sends no audio.
  Future<void> checkKey() async {
    await _send(() => _open('GET', '/models'));
  }

  /// Writes one FLAC piece, in [languageCode] or, when it's `null`,
  /// in the language Groq detects. [prompt] is a text hint Whisper reads
  /// before the audio; the app sends none.
  Future<List<GroqSegment>> transcribe(
    File piece, {
    required String? languageCode,
    String? prompt,
  }) async {
    await beforeUpload();
    final audio = await piece.readAsBytes();
    final boundary = 'studio${DateTime.now().microsecondsSinceEpoch}';
    final body = _multipartBody(
      boundary,
      audio,
      _transcriptionFields(languageCode, prompt),
    );
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

  /// Sends [chat] and returns the JSON object Groq replies with. Throws
  /// [GroqUnreadableReplyException] when the reply isn't one.
  Future<Map<String, Object?>> chatJson(GroqChatRequest chat) async {
    await beforeUpload();
    final body = utf8.encode(jsonEncode(_chatBody(chat)));
    final reply = await _send(() async {
      final request = await _open('POST', '/chat/completions');
      request.headers.contentType = ContentType.json;
      request.add(body);
      return request;
    });
    return _chatContentOf(reply);
  }

  Map<String, Object?> _chatBody(GroqChatRequest chat) => {
    'model': chat.model,
    'messages': [
      {'role': 'system', 'content': chat.instructions},
      {'role': 'user', 'content': chat.message},
    ],
    'response_format': {'type': 'json_object'},
    'temperature': 0,
    // Reasoning tokens count against the free plan's tokens per minute.
    if (chat.model.startsWith('openai/gpt-oss')) 'reasoning_effort': 'low',
  };

  Map<String, Object?> _chatContentOf(String reply) {
    try {
      final decoded = jsonDecode(reply) as Map<String, Object?>;
      final choices = decoded['choices']! as List<Object?>;
      final message =
          (choices.first! as Map<String, Object?>)['message']!
              as Map<String, Object?>;
      return jsonDecode(message['content']! as String) as Map<String, Object?>;
    } on Object catch (error) {
      throw GroqUnreadableReplyException('$error');
    }
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
      _reportAllowance(response.headers);
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

  /// Only replies to audio carry these headers; others report nothing.
  void _reportAllowance(HttpHeaders headers) {
    final report = onAllowance;
    if (report == null) {
      return;
    }
    final GroqAllowance allowance;
    try {
      allowance = _allowanceIn(headers);
    } on FormatException {
      return;
    }
    report(allowance);
  }

  /// Throws [FormatException] when a header is missing or unreadable.
  GroqAllowance _allowanceIn(HttpHeaders headers) {
    String header(String name) =>
        headers.value(name) ?? (throw FormatException('No $name'));
    final now = _clock();
    return GroqAllowance(
      limit: Duration(seconds: num.parse(header(_audioLimitHeader)).floor()),
      remaining: Duration(
        seconds: num.parse(header(_audioRemainingHeader)).floor(),
      ),
      resetsAt: now.add(parseGroqDuration(header(_audioResetHeader))),
      seenAt: now,
    );
  }

  Duration _retryAfter(HttpClientResponse response) {
    final seconds = num.tryParse(response.headers.value('retry-after') ?? '');
    return seconds == null
        ? _defaultWait
        : Duration(milliseconds: (seconds * 1000).round());
  }

  Map<String, String> _transcriptionFields(
    String? languageCode,
    String? prompt,
  ) {
    return {
      'model': model,
      'response_format': 'verbose_json',
      'timestamp_granularities[]': 'segment',
      'temperature': '0',
      'language': ?languageCode,
      'prompt': ?prompt,
    };
  }

  List<int> _multipartBody(
    String boundary,
    List<int> audio,
    Map<String, String> fields,
  ) {
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
