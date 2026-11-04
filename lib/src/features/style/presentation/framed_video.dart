import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:status_studio/src/features/export/domain/render_spec.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// [video] cropped, blurred or fitted the way Media3 will render it (spec
/// §6.3, §6.3.1), with a moving crop read at [videoTime] (spec FR-22). It
/// fills the space it is given, which has the output's aspect.
class FramedVideo extends StatelessWidget {
  const FramedVideo({
    super.key,
    required this.video,
    required this.frame,
    required this.sourceSize,
    required this.videoTime,
  });

  /// The unframed video; the blur uses it twice.
  final Widget video;
  final FrameSettings frame;

  /// The video's own frame size, which crops are measured in.
  final OutputSize sourceSize;
  final Duration videoTime;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _framed(Size(constraints.maxWidth, constraints.maxHeight)),
    );
  }

  Widget _framed(Size preview) {
    final source = sourceSize;
    if (frame.preset == AspectPreset.landscape16x9) {
      return Center(
        child: AspectRatio(
          aspectRatio: source.width / source.height,
          child: video,
        ),
      );
    }
    if (frame.preset != AspectPreset.free && frame.fill == FillMode.blur) {
      return _blurred(preview);
    }
    return _cropped(preview, cropRectAt(frame, source, videoTime));
  }

  Widget _cropped(Size preview, PixelRect crop) {
    final source = sourceSize;
    final scale = preview.width / crop.width;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(-crop.x * scale, -crop.y * scale),
          child: SizedBox(
            width: source.width * scale,
            height: source.height * scale,
            child: video,
          ),
        ),
      ),
    );
  }

  /// Media3's blur: the frame stretched and blurred behind a sharp copy.
  Widget _blurred(Size preview) {
    final source = sourceSize;
    final output = outputSizeFor(frame, source);
    final sharp = sharpFrameScale(source, output);
    final sigma = blurSigmaInSourcePixels * preview.width / source.width;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: video,
          ),
        ),
        Center(
          child: SizedBox(
            width: preview.width * sharp.x,
            height: preview.height * sharp.y,
            child: video,
          ),
        ),
      ],
    );
  }
}
