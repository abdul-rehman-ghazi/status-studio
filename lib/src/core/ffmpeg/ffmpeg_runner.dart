import 'dart:async';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FfmpegFailedException implements Exception {
  const FfmpegFailedException(this.log);

  final String log;

  @override
  String toString() => 'FfmpegFailedException: $log';
}

/// The app's single entry point to FFmpeg; runs off the UI isolate.
class FfmpegRunner {
  const FfmpegRunner();

  Future<void> run(
    List<String> arguments, {
    void Function(Duration processed)? onTime,
  }) async {
    final finished = Completer<void>();
    await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) => unawaited(_complete(session, finished)),
      null,
      onTime == null
          ? null
          : (Statistics statistics) =>
                onTime(Duration(milliseconds: statistics.getTime())),
    );
    return finished.future;
  }

  Future<void> cancel() => FFmpegKit.cancel();
}

/// Cancels one run, not every run: [FfmpegRunner.cancel] stops all sessions,
/// including a waveform's. Created before the run, bound to its session when
/// it starts; a cancel that comes first stops the run as it starts.
class FfmpegCancelHandle {
  int? _sessionId;
  var _cancelRequested = false;

  bool get isCancelled => _cancelRequested;

  Future<void> cancel() async {
    _cancelRequested = true;
    final id = _sessionId;
    if (id != null) {
      await FFmpegKit.cancel(id);
    }
  }

  Future<void> _bind(int? sessionId) async {
    _sessionId = sessionId;
    if (_cancelRequested && sessionId != null) {
      await FFmpegKit.cancel(sessionId);
    }
  }
}

/// A run that can be cancelled on its own through an [FfmpegCancelHandle].
class CancellableFfmpegRunner {
  const CancellableFfmpegRunner();

  Future<void> run(List<String> arguments, FfmpegCancelHandle handle) async {
    final finished = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) => unawaited(_complete(session, finished)),
    );
    await handle._bind(session.getSessionId());
    return finished.future;
  }
}

Future<void> _complete(FFmpegSession session, Completer<void> finished) async {
  final returnCode = await session.getReturnCode();
  if (ReturnCode.isSuccess(returnCode)) {
    finished.complete();
    return;
  }
  final log = await session.getAllLogsAsString() ?? '';
  finished.completeError(FfmpegFailedException(log));
}

final ffmpegRunnerProvider = Provider<FfmpegRunner>(
  (ref) => const FfmpegRunner(),
);

final cancellableFfmpegRunnerProvider = Provider<CancellableFfmpegRunner>(
  (ref) => const CancellableFfmpegRunner(),
);
