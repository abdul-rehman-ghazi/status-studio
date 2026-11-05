import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/export/data/overlay_painter.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/application/clip_frame_size_provider.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/framed_video.dart';
import 'package:status_studio/src/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

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

/// The reel at its output aspect, scaled to [maxWidth]: the clip's first
/// frame framed as the export frames it, with the caption and branding
/// placed by the export's own layout (spec FR-6, FR-7, FR-8).
class ReelPreview extends ConsumerWidget {
  const ReelPreview({super.key, required this.draft, required this.maxWidth});

  final ReelDraft draft;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceSize = previewSourceSize(ref, draft);
    final output = outputSizeFor(draft.frame, sourceSize);
    final width = maxWidth;
    final height = width * output.height / output.width;
    final source = previewClipSource(ref, draft);
    final clip = draft.clip;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: source == null || clip == null
                  ? _VideoPlaceholder(frame: draft.frame)
                  : _SourceFrame(
                      key: ValueKey(source.file.path),
                      source: source,
                      firstFrame: clip.start - source.offset,
                      videoTime: clip.start,
                      framing: (frame: draft.frame, sourceSize: sourceSize),
                    ),
            ),
            ReelOverlayLayer(
              spec: OverlaySpec(
                output: output,
                caption: _firstLineCaption(draft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview is the clip's first frame, so it shows the caption's first
/// line, as the export does at that moment (spec FR-7a).
CaptionSettings _firstLineCaption(ReelDraft draft) {
  if (draft.clip == null) {
    return draft.caption;
  }
  final cues = draft.captionCues;
  return draft.caption.copyWith(text: cues.isEmpty ? '' : cues.first.text);
}

typedef _Framing = ({FrameSettings frame, OutputSize sourceSize});

/// One still frame of the clip, cropped, blurred or fitted the way Media3
/// will render it (spec §6.3, §6.3.1).
class _SourceFrame extends ConsumerStatefulWidget {
  const _SourceFrame({
    super.key,
    required this.source,
    required this.firstFrame,
    required this.videoTime,
    required this.framing,
  });

  final ClipSource source;

  /// Where the clip starts inside the file.
  final Duration firstFrame;

  /// The same moment in video time, where a moving crop is read.
  final Duration videoTime;
  final _Framing framing;

  @override
  ConsumerState<_SourceFrame> createState() => _SourceFrameState();
}

class _SourceFrameState extends ConsumerState<_SourceFrame> {
  late final VideoPlayerController _player = ref.read(
    videoPlayerFactoryProvider,
  )(widget.source.file);

  @override
  void initState() {
    super.initState();
    unawaited(_showFirstFrame());
  }

  /// A clip that won't open keeps the placeholder: the preview is a guide,
  /// and Fine-tune already told the user about an unplayable video.
  Future<void> _showFirstFrame() async {
    try {
      await _player.initialize();
      await _player.seekTo(widget.firstFrame);
    } on Object {
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_player.value.isInitialized) {
      return _VideoPlaceholder(frame: widget.framing.frame);
    }
    return FramedVideo(
      video: VideoPlayer(_player),
      frame: widget.framing.frame,
      sourceSize: widget.framing.sourceSize,
      videoTime: widget.videoTime,
    );
  }
}

/// Stands in for the video frame until the clip has been downloaded.
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
            Text(brandingText, style: brandingTextStyle(logo)),
          ],
        ),
      ),
    );
  }
}
