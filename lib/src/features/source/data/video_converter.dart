import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _methods = MethodChannel('status_studio/render');

abstract interface class VideoConverter {
  /// Writes [inputPath] as H.264 video with AAC audio to [outputPath].
  /// Throws [VideoNotConvertibleException] when the phone can't.
  Future<void> convertToH264({
    required String inputPath,
    required String outputPath,
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
  }) async {
    try {
      await _methods.invokeMethod<void>('convert', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
    } on PlatformException catch (error) {
      throw VideoNotConvertibleException(error.message ?? error.code);
    }
  }
}

final videoConverterProvider = Provider<VideoConverter>(
  (ref) => const NativeVideoConverter(),
);
