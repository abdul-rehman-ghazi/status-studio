import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/export/data/overlay_painter.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/application/clip_frame_size_provider.dart';
import 'package:status_studio/src/features/style/domain/caption_ink.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Frame size used until the clip file has been probed.
const assumedSourceSize = OutputSize(1920, 1080);

/// The kept video for [draft], once Fine-tune has opened it.
ClipSource? previewClipSource(WidgetRef ref, ReelDraft draft) {
  final video = draft.video;
  if (video == null) {
    return null;
  }
  return ref.watch(clipSourceProvider(video.videoId)).value;
}

/// The clip file's frame size, or [assumedSourceSize] until it's known.
OutputSize previewSourceSize(WidgetRef ref, ReelDraft draft) {
  final source = previewClipSource(ref, draft);
  if (source == null) {
    return assumedSourceSize;
  }
  return ref.watch(clipFrameSizeProvider(source)).value ?? assumedSourceSize;
}

/// The caption and branding laid out at full output size by the export's
/// own layout, then scaled to the preview, so text wraps exactly as in the
/// exported reel.
class ReelOverlayLayer extends StatelessWidget {
  const ReelOverlayLayer({super.key, required this.spec});

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
                if (text.trim().isNotEmpty) ..._caption(spec.caption, layout),
                _brandingPill(layout),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _caption(CaptionSettings caption, OverlayLayout layout) {
    final box = layout.captionBox;
    final ink = captionInkFor(caption.appearance);
    final boxColour = ink.box;
    final text = caption.text;
    return [
      if (boxColour != null)
        Positioned.fromRect(
          rect: box,
          child: ColoredBox(color: boxColour),
        ),
      Positioned(
        left: box.center.dx - layout.captionTextMaxWidth / 2,
        top: box.top + layout.captionPadding,
        width: layout.captionTextMaxWidth,
        height: box.height - 2 * layout.captionPadding,
        // The Shadow look's blur reaches past the text; the export lets it.
        child: ClipRect(
          clipBehavior: boxColour == null ? Clip.none : Clip.hardEdge,
          child: Text(
            text,
            textAlign: TextAlign.center,
            textDirection: captionTextDirection(text),
            maxLines: layout.captionMaxLines,
            overflow: TextOverflow.ellipsis,
            style: captionTextStyle(text, layout.captionFontSize, ink),
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
          color: ReelColors.scrim.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(logo),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoMark(size: logo),
            SizedBox(width: logo * 0.3),
            Text(brandingText, style: brandingTextStyle(logo)),
          ],
        ),
      ),
    );
  }
}
