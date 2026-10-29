import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
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
    final captionOnTop = draft.caption.position == CaptionPosition.top;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: _VideoPlaceholder(frame: draft.frame)),
            if (draft.caption.text.trim().isNotEmpty)
              _CaptionBlock(
                caption: draft.caption,
                frameSize: Size(width, height),
              ),
            _BrandingPill(
              frameWidth: width,
              alignment: captionOnTop
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
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

class _CaptionBlock extends StatelessWidget {
  const _CaptionBlock({required this.caption, required this.frameSize});

  final CaptionSettings caption;
  final Size frameSize;

  @override
  Widget build(BuildContext context) {
    final edgeMargin = frameSize.height * 0.06;
    final onTop = caption.position == CaptionPosition.top;
    return Positioned(
      left: 0,
      right: 0,
      top: onTop ? edgeMargin : null,
      bottom: onTop ? null : edgeMargin,
      child: Center(
        child: ConstrainedBox(
          // FR-7's shrink-then-ellipsis rule is applied by the M5 renderer;
          // the preview only caps the block at the same height.
          constraints: BoxConstraints(
            maxHeight: frameSize.height * 0.35,
            maxWidth: frameSize.width * 0.92,
          ),
          child: ClipRect(
            child: Container(
              padding: EdgeInsets.all(frameSize.width * 0.02),
              color: AppColors.overlay.withValues(alpha: 0.38),
              child: ScriptText(
                caption.text,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: frameSize.width * caption.size.widthFraction,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandingPill extends StatelessWidget {
  const _BrandingPill({required this.frameWidth, required this.alignment});

  final double frameWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final logoSize = frameWidth * 0.045;
    final inset = frameWidth * 0.04;
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: Align(
          alignment: alignment,
          child: Container(
            padding: EdgeInsets.all(logoSize * 0.2),
            decoration: BoxDecoration(
              color: AppColors.overlay.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(logoSize),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoMark(size: logoSize),
                SizedBox(width: logoSize * 0.3),
                Text(
                  'Status Studio',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: AppFonts.ui,
                    fontWeight: FontWeight.w600,
                    fontSize: logoSize * 0.55,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
