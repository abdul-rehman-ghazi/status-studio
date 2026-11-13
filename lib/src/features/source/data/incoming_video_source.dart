import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _channel = MethodChannel('status_studio/video_in');

/// Videos (spec FR-1) and, on Android, YouTube links (FR-35) shared into the
/// app from elsewhere: the one that launched it first, then any later share
/// while it runs.
abstract interface class IncomingVideoSource {
  /// A broadcast stream. A video that fails to copy arrives as an error:
  /// [InsufficientStorageException] or [VideoUnreadableException].
  Stream<IncomingShare> get shares;
}

/// Turns the platform's share messages into shares: anything that is
/// neither a link nor a video is dropped, and so is a video reported a
/// second time.
Stream<IncomingShare> incomingSharesFrom(
  Stream<Map<Object?, Object?>> messages,
) {
  final reportedPaths = <String>{};
  bool isFirstReport(IncomingShare share) =>
      share is! IncomingVideo || reportedPaths.add(share.path);

  return messages
      .map(_shareFrom)
      .where((share) => share != null)
      .cast<IncomingShare>()
      .where(isFirstReport);
}

/// Null for a message that is neither, which the stream drops.
IncomingShare? _shareFrom(Map<Object?, Object?> message) {
  final link = message['link'];
  if (link is String && link.isNotEmpty) {
    return IncomingLink(link);
  }
  return _isVideoShare(message) ? _videoFrom(message) : null;
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

/// The platform side: `VideoInChannel` in Kotlin on Android, in Swift on iOS
/// (fed by the Share Extension). Where the channel doesn't exist (tests) no
/// video ever arrives.
class PlatformIncomingVideoSource implements IncomingVideoSource {
  PlatformIncomingVideoSource() {
    // The controller buffers until the first listener subscribes, so the
    // launch share is not lost; `asBroadcastStream` then serves any number
    // of listeners and tells us when the first arrives and the last leaves.
    shares = incomingSharesFrom(_messages.stream).asBroadcastStream(
      onListen: (subscription) {
        subscription.resume();
        unawaited(_startListening());
      },
      onCancel: (subscription) {
        subscription.pause();
        unawaited(_stopListening());
      },
    );
  }

  final _messages = StreamController<Map<Object?, Object?>>();
  var _listening = false;

  @override
  late final Stream<IncomingShare> shares;

  Future<void> _startListening() async {
    _listening = true;
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

  /// Tells the platform first and drops the handler after: a share pushed in
  /// between would otherwise reach nobody. From then on the platform keeps
  /// shares for the next `listen`.
  Future<void> _stopListening() async {
    _listening = false;
    try {
      await _channel.invokeMethod<void>('stopListening');
    } on MissingPluginException {
      // No platform side, so there is nothing to keep shares.
    }
    if (!_listening) _channel.setMethodCallHandler(null);
  }

  Future<void> _onPlatformCall(MethodCall call) async =>
      _dispatch(call.method, call.arguments);

  void _dispatch(String method, Object? arguments) {
    if (arguments is! Map<Object?, Object?>) return;
    switch (method) {
      case 'incomingVideo' || 'incomingLink':
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
