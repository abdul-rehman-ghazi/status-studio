import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// Spec §6.3.1: Media3's Gaussian blur behind the sharp frame.
const _blurSigma = 20.0;

/// Everything one export needs.
@immutable
class RenderJob {
  const RenderJob({
    required this.source,
    required this.clip,
    required this.frame,
    required this.sourceSize,
    required this.overlayPath,
    required this.outputPath,
  });

  final ClipSource source;
  final ClipRange clip;
  final FrameSettings frame;

  /// The clip file's frame size, which crops are measured in.
  final OutputSize sourceSize;
  final String overlayPath;
  final String outputPath;

  @override
  bool operator ==(Object other) =>
      other is RenderJob &&
      other.source == source &&
      other.clip == clip &&
      other.frame == frame &&
      other.sourceSize == sourceSize &&
      other.overlayPath == overlayPath &&
      other.outputPath == outputPath;

  @override
  int get hashCode =>
      Object.hash(source, clip, frame, sourceSize, overlayPath, outputPath);
}

/// The map sent to the Kotlin renderer on `status_studio/render`.
Map<String, Object?> renderSpecFor(RenderJob job) {
  final output = outputSizeFor(job.frame, job.sourceSize);
  final fill = _fillOf(job.frame);
  return {
    'inputPath': job.source.file.path,
    'outputPath': job.outputPath,
    'overlayPath': job.overlayPath,
    // The clip file starts at the source offset, not at video time zero.
    'clipStartMs': (job.clip.start - job.source.offset).inMilliseconds,
    'clipEndMs': (job.clip.end - job.source.offset).inMilliseconds,
    'outputWidth': output.width,
    'outputHeight': output.height,
    'fill': fill,
    if (fill == 'crop') 'crop': _ndcCrop(job),
    if (fill == 'blur') 'blurSigma': _blurSigma,
    'videoMimeType': 'video/avc',
    'audioMimeType': 'audio/mp4a-latm',
  };
}

String _fillOf(FrameSettings frame) {
  if (frame.preset == AspectPreset.free) {
    return 'crop';
  }
  if (frame.preset == AspectPreset.landscape16x9) {
    return 'none';
  }
  return switch (frame.fill) {
    FillMode.crop => 'crop',
    FillMode.blur => 'blur',
  };
}

Map<String, double> _ndcCrop(RenderJob job) {
  final ndc = toNdc(cropRectFor(job.frame, job.sourceSize), job.sourceSize);
  return {
    'left': ndc.left,
    'right': ndc.right,
    'bottom': ndc.bottom,
    'top': ndc.top,
  };
}
