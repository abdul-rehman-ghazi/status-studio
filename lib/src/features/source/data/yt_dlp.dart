import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _channel = MethodChannel('status_studio/ytdlp');

enum YtDlpUpdate { updated, upToDate }

/// yt-dlp on the phone: everything it knows about one video, as its `-J`
/// JSON. Failures are thrown as the typed exceptions in
/// `source_errors.dart`.
abstract interface class YtDlp {
  /// Without a JavaScript runtime: about twice as fast, but only YouTube
  /// clients that need no challenge solving answer (spec §10 Q4).
  /// [pageUrl] is any page yt-dlp reads (FR-50).
  Future<Map<String, Object?>> quickVideoInfo(String pageUrl);

  /// With QuickJS solving YouTube's challenges, for videos the quick run
  /// can't read.
  Future<Map<String, Object?>> videoInfo(String pageUrl);

  /// Fetches the newest stable yt-dlp (about 3 MB).
  Future<YtDlpUpdate> update();

  Future<String> version();

  /// Downloads the audio only to [outputPath] (spec FR-36), reporting the
  /// fraction done to [onProgress]. The file appears only once whole. A
  /// site with no sound-only stream gives its smallest whole file (FR-50).
  Future<void> downloadAudio({
    required String pageUrl,
    required String outputPath,
    required void Function(double fraction) onProgress,
  });

  /// Stops the download writing [outputPath]; its future then fails.
  Future<void> cancelDownload(String outputPath);
}

class PlatformYtDlp implements YtDlp {
  PlatformYtDlp() {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  /// Keyed by output path, which the platform uses as the process ID.
  final _progressListeners = <String, void Function(double)>{};

  @override
  Future<void> downloadAudio({
    required String pageUrl,
    required String outputPath,
    required void Function(double fraction) onProgress,
  }) async {
    _progressListeners[outputPath] = onProgress;
    try {
      await _call<String>('downloadAudio', {
        'pageUrl': pageUrl,
        'outputPath': outputPath,
      });
    } finally {
      _progressListeners.remove(outputPath);
    }
  }

  @override
  Future<void> cancelDownload(String outputPath) =>
      _channel.invokeMethod<void>('cancel', outputPath);

  Future<void> _onPlatformCall(MethodCall call) async {
    final arguments = call.arguments;
    if (call.method != 'downloadProgress' || arguments is! Map) {
      return;
    }
    final listener = _progressListeners[arguments['processId']];
    final fraction = arguments['fraction'];
    if (listener != null && fraction is num) {
      listener(fraction.toDouble().clamp(0, 1));
    }
  }

  @override
  Future<Map<String, Object?>> quickVideoInfo(String pageUrl) =>
      _info('quickVideoInfo', pageUrl);

  @override
  Future<Map<String, Object?>> videoInfo(String pageUrl) =>
      _info('videoInfo', pageUrl);

  @override
  Future<YtDlpUpdate> update() async {
    final status = await _call<String>('update');
    return status == 'updated' ? YtDlpUpdate.updated : YtDlpUpdate.upToDate;
  }

  @override
  Future<String> version() => _call<String>('version');

  /// The JSON is about 600 KB, so it's decoded off the UI thread.
  Future<Map<String, Object?>> _info(String method, String pageUrl) async {
    final json = await _call<String>(method, pageUrl);
    return Isolate.run(() => jsonDecode(json) as Map<String, Object?>);
  }

  Future<T> _call<T>(String method, [Object? arguments]) async {
    try {
      final reply = await _channel.invokeMethod<T>(method, arguments);
      if (reply == null) {
        throw SiteChangedException('yt-dlp returned nothing for $method.');
      }
      return reply;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(mapYtDlpError(error), stackTrace);
    }
  }
}

const _unavailable = [
  'video unavailable',
  'private video',
  'sign in to confirm your age',
  'members-only',
  "this channel's members",
  'live event will begin',
  'premieres in',
  'has been removed',
  'is not available',
];

const _offline = [
  'urlopen error',
  'getaddrinfo',
  'errno 7]',
  'errno 101]',
  'no address associated',
  'temporary failure in name resolution',
  'network is unreachable',
  'timed out',
  'connection reset',
];

const _unsupported = ['unsupported url'];

/// Instagram's own wording, which also says "not available".
const _loginWall = ['rate-limit reached', 'login required'];

/// Phrases yt-dlp adds to many errors; read only after the more precise
/// lists, so YouTube's private and age-restricted videos keep their message.
const _loginHints = ['log in', 'login', 'sign in', 'cookies'];

/// YouTube asking every app to prove it isn't a bot is not about this video:
/// a newer yt-dlp or a later try may get through (*Claude's call*, FR-50).
const _botCheck = ['not a bot'];

/// yt-dlp's error output decides (spec §8, FR-50): a site yt-dlp has no
/// reader for, a video behind a login, a video the site won't give, no
/// network, or anything else, which is taken as the site having changed.
Object mapYtDlpError(Object error) {
  if (error is! PlatformException) {
    return mapIoError(error);
  }
  return _mapYtDlpMessage('${error.message}');
}

Object _mapYtDlpMessage(String message) {
  final lowerMessage = message.toLowerCase();
  bool saysAny(List<String> phrases) => phrases.any(lowerMessage.contains);
  if (saysAny(_unsupported)) {
    return UnsupportedSiteException(message);
  }
  if (saysAny(_loginWall)) {
    return LoginRequiredException(message);
  }
  if (saysAny(_unavailable)) {
    return VideoUnavailableException(message);
  }
  if (saysAny(_offline)) {
    return OfflineException(message);
  }
  if (saysAny(_botCheck) || !saysAny(_loginHints)) {
    return SiteChangedException(message);
  }
  return LoginRequiredException(message);
}

final ytDlpProvider = Provider<YtDlp>((ref) => PlatformYtDlp());
