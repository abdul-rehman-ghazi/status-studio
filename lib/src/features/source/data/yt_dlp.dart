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
  Future<Map<String, Object?>> quickVideoInfo(String videoId);

  /// With QuickJS solving YouTube's challenges, for videos the quick run
  /// can't read.
  Future<Map<String, Object?>> videoInfo(String videoId);

  /// Fetches the newest stable yt-dlp (about 3 MB).
  Future<YtDlpUpdate> update();

  Future<String> version();
}

class PlatformYtDlp implements YtDlp {
  const PlatformYtDlp();

  @override
  Future<Map<String, Object?>> quickVideoInfo(String videoId) =>
      _info('quickVideoInfo', videoId);

  @override
  Future<Map<String, Object?>> videoInfo(String videoId) =>
      _info('videoInfo', videoId);

  @override
  Future<YtDlpUpdate> update() async {
    final status = await _call<String>('update');
    return status == 'updated' ? YtDlpUpdate.updated : YtDlpUpdate.upToDate;
  }

  @override
  Future<String> version() => _call<String>('version');

  /// The JSON is about 600 KB, so it's decoded off the UI thread.
  Future<Map<String, Object?>> _info(String method, String videoId) async {
    final json = await _call<String>(method, videoId);
    return Isolate.run(() => jsonDecode(json) as Map<String, Object?>);
  }

  Future<T> _call<T>(String method, [Object? arguments]) async {
    try {
      final reply = await _channel.invokeMethod<T>(method, arguments);
      if (reply == null) {
        throw YouTubeChangedException('yt-dlp returned nothing for $method.');
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

/// yt-dlp's error output decides (spec §8): a video YouTube won't give,
/// no network, or anything else, which is taken as YouTube having changed.
Object mapYtDlpError(Object error) {
  if (error is! PlatformException) {
    return mapIoError(error);
  }
  final message = (error.message ?? '').toLowerCase();
  if (_unavailable.any(message.contains)) {
    return VideoUnavailableException('${error.message}');
  }
  if (_offline.any(message.contains)) {
    return OfflineException('${error.message}');
  }
  return YouTubeChangedException('${error.message}');
}

final ytDlpProvider = Provider<YtDlp>((ref) => const PlatformYtDlp());
