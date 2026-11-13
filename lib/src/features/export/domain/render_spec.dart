import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// Spec §6.3.1: Media3's Gaussian blur behind the sharp frame.
const _blurSigma = 20.0;

/// One caption line's overlay image and when it shows, counted from the
/// clip's start (spec FR-7a).
@immutable
class RenderCue {
  const RenderCue({
    required this.start,
    required this.end,
    required this.overlayPath,
  });

  final Duration start;
  final Duration end;
  final String overlayPath;

  @override
  bool operator ==(Object other) =>
      other is RenderCue &&
      other.start == start &&
      other.end == end &&
      other.overlayPath == overlayPath;

  @override
  int get hashCode => Object.hash(start, end, overlayPath);
}

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
    this.captionCues = const [],
    this.fade = Duration.zero,
    this.soundGain = 1,
  });

  final ClipSource source;
  final ClipRange clip;
  final FrameSettings frame;

  /// The clip file's frame size, which crops are measured in.
  final OutputSize sourceSize;

  /// The branding on its own, shown whenever no caption line is.
  final String overlayPath;
  final String outputPath;
  final List<RenderCue> captionCues;

  /// How long the picture fades in and out; zero for no fade (spec FR-33).
  final Duration fade;

  /// The linear gain for the sound; 1 leaves it as it is (spec FR-42).
  final double soundGain;

  @override
  bool operator ==(Object other) =>
      other is RenderJob &&
      other.source == source &&
      other.clip == clip &&
      other.frame == frame &&
      other.sourceSize == sourceSize &&
      other.overlayPath == overlayPath &&
      other.outputPath == outputPath &&
      listEquals(other.captionCues, captionCues) &&
      other.fade == fade &&
      other.soundGain == soundGain;

  @override
  int get hashCode => Object.hash(
    source,
    clip,
    frame,
    sourceSize,
    overlayPath,
    outputPath,
    Object.hashAll(captionCues),
    fade,
    soundGain,
  );
}

/// The map sent to the Kotlin renderer on `status_studio/render`.
Map<String, Object?> renderSpecFor(RenderJob job) {
  final output = outputSizeFor(job.frame, job.sourceSize);
  final fill = _fillOf(job.frame);
  return {
    'inputPath': job.source.file.path,
    'outputPath': job.outputPath,
    'overlayPath': job.overlayPath,
    'captionCues': [
      for (final cue in job.captionCues)
        {
          'startMs': cue.start.inMilliseconds,
          'endMs': cue.end.inMilliseconds,
          'path': cue.overlayPath,
        },
    ],
    // The clip file starts at the source offset, not at video time zero.
    'clipStartMs': (job.clip.start - job.source.offset).inMilliseconds,
    'clipEndMs': (job.clip.end - job.source.offset).inMilliseconds,
    'outputWidth': output.width,
    'outputHeight': output.height,
    'fill': fill,
    if (fill == 'crop' && job.frame.cropPath.isEmpty) 'crop': _ndcCrop(job),
    if (fill == 'crop' && !job.frame.cropPath.isEmpty)
      'cropKeyframes': _cropKeyframes(job),
    if (fill == 'blur') ..._blurSettings(job.sourceSize, output),
    if (job.fade > Duration.zero) 'fadeMs': job.fade.inMilliseconds,
    if (job.soundGain > 1) 'soundGain': job.soundGain,
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

Map<String, double> _blurSettings(OutputSize source, OutputSize output) {
  final sharp = sharpFrameScale(source, output);
  return {
    'blurSigma': _blurSigma,
    'sharpScaleX': sharp.x,
    'sharpScaleY': sharp.y,
  };
}

/// Media3's blur draws the whole frame sharp at this share of the output,
/// over a blurred copy stretched to the output. The sharp frame keeps its
/// aspect and fits the output width (or height, for a taller source). The
/// Style preview draws the same.
({double x, double y}) sharpFrameScale(OutputSize source, OutputSize output) {
  final sourceAspect = source.width / source.height;
  final outputAspect = output.width / output.height;
  if (sourceAspect >= outputAspect) {
    return (x: 1.0, y: outputAspect / sourceAspect);
  }
  return (x: sourceAspect / outputAspect, y: 1.0);
}

/// Spec §6.3.1's σ is in source pixels; the preview scales it.
const blurSigmaInSourcePixels = _blurSigma;

Map<String, double> _ndcCrop(RenderJob job) {
  final ndc = toNdc(cropRectFor(job.frame, job.sourceSize), job.sourceSize);
  return {
    'left': ndc.left,
    'right': ndc.right,
    'bottom': ndc.bottom,
    'top': ndc.top,
  };
}

/// The moving crop (spec §6.3.2): each keyframe's rectangle with its time
/// counted from the clip start.
List<Map<String, Object?>> _cropKeyframes(RenderJob job) {
  return [
    for (final keyframe in job.frame.cropPath.keyframes)
      {
        'timeMs': (keyframe.time - job.clip.start).inMilliseconds,
        'arrival': keyframe.arrival == CropArrival.cut ? 'cut' : 'glide',
        ..._ndcRectAt(job, keyframe.time),
      },
  ];
}

Map<String, double> _ndcRectAt(RenderJob job, Duration videoTime) {
  final rect = cropRectAt(job.frame, job.sourceSize, videoTime);
  final ndc = toNdc(rect, job.sourceSize);
  return {
    'left': ndc.left,
    'right': ndc.right,
    'bottom': ndc.bottom,
    'top': ndc.top,
  };
}
