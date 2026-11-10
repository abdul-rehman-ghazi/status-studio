import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _methods = MethodChannel('status_studio/render');

/// One stream for every conversion: each listen on a new stream would take
/// the native side's only sink from the one before.
final Stream<Object?> _conversionEvents = const EventChannel(
  'status_studio/render/conversion',
).receiveBroadcastStream();

abstract interface class VideoConverter {
  /// Writes [inputPath] as H.264 video with AAC audio to [outputPath],
  /// telling [onProgress] how far it is (0 to 1) as it goes. Throws
  /// [VideoNotConvertibleException] when the phone can't.
  Future<void> convertToH264({
    required String inputPath,
    required String outputPath,
    required void Function(double fraction) onProgress,
  });
}

/// Converts with the native renderer (spec FR-1, M31): Media3 Transformer on
/// Android, AVFoundation on iOS. The call returns when the file is written.
class NativeVideoConverter implements VideoConverter {
  const NativeVideoConverter();

  @override
  Future<void> convertToH264({
    required String inputPath,
    required String outputPath,
    required void Function(double fraction) onProgress,
  }) async {
    final progress = _conversionEvents.listen((event) {
      if (_fractionFor(outputPath, event) case final fraction?) {
        onProgress(fraction);
      }
    });
    try {
      await _methods.invokeMethod<void>('convert', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
    } on PlatformException catch (error) {
      throw VideoNotConvertibleException(error.message ?? error.code);
    } finally {
      await progress.cancel();
    }
  }
}

/// The fraction in [event] when it is about [outputPath]'s conversion.
double? _fractionFor(String outputPath, Object? event) {
  if (event case {'outputPath': final String path, 'value': final num value}
      when path == outputPath) {
    return value.toDouble().clamp(0, 1);
  }
  return null;
}

final videoConverterProvider = Provider<VideoConverter>(
  (ref) => const NativeVideoConverter(),
);
