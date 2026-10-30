import 'package:flutter/material.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/export/data/overlay_painter.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Source frame size assumed until M2 reads the real one from the video.
const assumedSourceSize = OutputSize(1920, 1080);

/// The reel at its output aspect, scaled to [maxWidth], with the caption and
/// branding placed as the export will place them (spec FR-7, FR-8).
class ReelPreview extends StatelessWidget {
  const ReelPreview({super.key, required this.draft, required this.maxWidth});

  final ReelDraft draft;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final output = outputSizeFor(draft.frame, assumedSourceSize);
    final width = maxWidth;
    final height = width * output.height / output.width;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: _VideoPlaceholder(frame: draft.frame)),
            _OverlayLayer(
              spec: OverlaySpec(output: output, caption: draft.caption),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for the video frame until M2 brings real video.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.frame});

  final FrameSettings frame;

  @override
  Widget build(BuildContext context) {
    const movieIcon = Icon(Icons.movie_outlined, color: AppColors.textMuted);
    if (frame.offersFill && frame.fill == FillMode.blur) {
      return const ColoredBox(
        color: AppColors.background,
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: AppColors.surface, child: movieIcon),
          ),
        ),
      );
    }
    return const ColoredBox(color: AppColors.surface, child: movieIcon);
  }
}

/// The caption and branding laid out at full output size by the export's
/// own layout, then scaled to the preview, so text wraps exactly as in the
/// exported reel.
class _OverlayLayer extends StatelessWidget {
  const _OverlayLayer({required this.spec});

  final OverlaySpec spec;

  @override
  Widget build(BuildContext context) {
    final layout = layoutOverlay(spec, measureText: measureCaptionText);
    final text = spec.caption.text;
    return Positioned.fill(
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: spec.output.width.toDouble(),
          height: spec.output.height.toDouble(),
          // The export paints at a fixed size; system text scaling would
          // make the preview disagree with it.
          child: MediaQuery.withNoTextScaling(
            child: Stack(
              children: [
                if (text.trim().isNotEmpty) ..._caption(text, layout),
                _brandingPill(layout),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _caption(String text, OverlayLayout layout) {
    final box = layout.captionBox;
    return [
      Positioned.fromRect(
        rect: box,
        child: ColoredBox(color: AppColors.overlay.withValues(alpha: 0.38)),
      ),
      Positioned(
        left: box.center.dx - layout.captionTextMaxWidth / 2,
        top: box.top + layout.captionPadding,
        width: layout.captionTextMaxWidth,
        height: box.height - 2 * layout.captionPadding,
        child: ClipRect(
          child: Text(
            text,
            textAlign: TextAlign.center,
            textDirection: captionTextDirection(text),
            maxLines: layout.captionMaxLines,
            overflow: TextOverflow.ellipsis,
            style: captionTextStyle(text, layout.captionFontSize),
          ),
        ),
      ),
    ];
  }

  Widget _brandingPill(OverlayLayout layout) {
    final logo = layout.logoSize;
    return Positioned(
      left: layout.brandingOrigin.dx,
      top: layout.brandingOrigin.dy,
      child: Container(
        padding: EdgeInsets.all(logo * brandingPillPadding),
        decoration: BoxDecoration(
          color: AppColors.overlay.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(logo),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoMark(size: logo),
            SizedBox(width: logo * 0.3),
            Text(
              brandingText,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontFamily: AppFonts.ui,
                fontWeight: FontWeight.w600,
                fontSize: logo * 0.55,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
