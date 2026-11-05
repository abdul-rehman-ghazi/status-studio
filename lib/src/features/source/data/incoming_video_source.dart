import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _channel = MethodChannel('status_studio/video_in');

/// Videos shared into the app from elsewhere (spec FR-1): the one that
/// launched it first, then any later share while it runs.
abstract interface class IncomingVideoSource {
  /// Single-subscription. A share that fails to copy arrives as an error:
  /// [InsufficientStorageException] or [VideoUnreadableException].
  Stream<IncomingVideo> get videos;
}

/// Turns the platform's share messages into videos: anything that isn't a
/// video is dropped, and so is a share reported a second time.
Stream<IncomingVideo> incomingVideosFrom(
  Stream<Map<Object?, Object?>> messages,
) {
  final reportedPaths = <String>{};
  bool isFirstReport(IncomingVideo video) => reportedPaths.add(video.path);

  return messages.where(_isVideoShare).map(_videoFrom).where(isFirstReport);
}

bool _isVideoShare(Map<Object?, Object?> message) {
  final path = message['path'];
  final mimeType = message['mimeType'];
  return path is String &&
      path.isNotEmpty &&
      mimeType is String &&
      mimeType.startsWith('video/');
}

IncomingVideo _videoFrom(Map<Object?, Object?> message) {
  final path = message['path']! as String;
  final displayName = message['displayName'];
  return IncomingVideo(
    path: path,
    displayName: displayName is String && displayName.isNotEmpty
        ? displayName
        : path.split('/').last,
  );
}

/// The Android side, `VideoInChannel` in Kotlin. Where the channel
/// doesn't exist (iOS until M26, tests) no video ever arrives.
class PlatformIncomingVideoSource implements IncomingVideoSource {
  PlatformIncomingVideoSource() {
    _messages = StreamController<Map<Object?, Object?>>(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    videos = incomingVideosFrom(_messages.stream);
  }

  late final StreamController<Map<Object?, Object?>> _messages;

  @override
  late final Stream<IncomingVideo> videos;

  Future<void> _startListening() async {
    _channel.setMethodCallHandler(_onPlatformCall);
    try {
      final waiting = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'listen',
      );
      for (final entry in waiting ?? const <Map<Object?, Object?>>[]) {
        _dispatch(entry['method']! as String, entry['arguments']);
      }
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _stopListening() async {
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('stopListening');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _onPlatformCall(MethodCall call) async =>
      _dispatch(call.method, call.arguments);

  void _dispatch(String method, Object? arguments) {
    if (arguments is! Map<Object?, Object?>) return;
    switch (method) {
      case 'incomingVideo':
        _messages.add(arguments);
      case 'incomingVideoFailed':
        _messages.addError(_copyFailure(arguments));
    }
  }

  Exception _copyFailure(Map<Object?, Object?> failure) {
    final reason = '${failure['message']}';
    return failure['code'] == 'no_space'
        ? InsufficientStorageException(reason)
        : VideoUnreadableException(reason);
  }
}

final incomingVideoSourceProvider = Provider<IncomingVideoSource>(
  (ref) => PlatformIncomingVideoSource(),
);
