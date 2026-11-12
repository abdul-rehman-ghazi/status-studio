import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/join_plan.dart';

const _methods = MethodChannel('status_studio/render');

/// Shared with conversions: each listen on a new stream would take the
/// native side's only sink from the one before.
final Stream<Object?> _progressEvents = const EventChannel(
  'status_studio/render/conversion',
).receiveBroadcastStream();

abstract interface class ClipJoiner {
  /// Writes [plan] as one H.264/AAC file at [outputPath], telling
  /// [onProgress] how far it is (0 to 1). Throws [JoinFailedException].
  Future<void> join(
    JoinPlan plan,
    String outputPath,
    void Function(double fraction) onProgress,
  );

  /// Stops the running join; its [join] then fails.
  Future<void> cancel();
}

/// Joins with Media3 on Android (spec FR-37). iOS has no link input, so
/// nothing calls it there.
class NativeClipJoiner implements ClipJoiner {
  const NativeClipJoiner();

  @override
  Future<void> join(
    JoinPlan plan,
    String outputPath,
    void Function(double fraction) onProgress,
  ) async {
    final progress = _progressEvents.listen((event) {
      if (event case {'outputPath': final String path, 'value': final num value}
          when path == outputPath) {
        onProgress(value.toDouble().clamp(0, 1));
      }
    });
    try {
      await _methods.invokeMethod<void>('join', plan.toChannel(outputPath));
    } on PlatformException catch (error) {
      throw JoinFailedException(error.message ?? error.code);
    } finally {
      await progress.cancel();
    }
  }

  @override
  Future<void> cancel() => _methods.invokeMethod<void>('cancelJoin');
}

final clipJoinerProvider = Provider<ClipJoiner>(
  (ref) => const NativeClipJoiner(),
);
