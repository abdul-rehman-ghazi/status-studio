import 'package:flutter/material.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/presentation/playhead_redraw.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/domain/caption_cues.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/framed_video.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';

/// The reel as it will look at the playhead: [video] framed with the crop
/// where it is then, the lyric line due, and the branding (spec FR-21,
/// FR-22). It follows the playhead frame by frame while playing.
class ReelStage extends StatefulWidget {
  const ReelStage({
    super.key,
    required this.draft,
    required this.sourceSize,
    required this.video,
    required this.playhead,
  });

  final ReelDraft draft;
  final OutputSize sourceSize;
  final Widget video;
  final ClipPlayhead playhead;

  @override
  State<ReelStage> createState() => _ReelStageState();
}

class _ReelStageState extends State<ReelStage>
    with SingleTickerProviderStateMixin {
  late final PlayheadRedraw _redraw;

  @override
  void initState() {
    super.initState();
    _redraw = PlayheadRedraw(
      vsync: this,
      playhead: widget.playhead,
      isMounted: () => mounted,
      redraw: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _redraw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final clip = draft.clip;
    if (clip == null) {
      throw StateError('The reel stage was shown without a clip.');
    }
    final time = widget.playhead.position;
    final output = outputSizeFor(draft.frame, widget.sourceSize);
    final due = cueDueAt(draft.captionCues, time - clip.start);
    return AspectRatio(
      aspectRatio: output.width / output.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: FramedVideo(
              video: widget.video,
              frame: draft.frame,
              sourceSize: widget.sourceSize,
              videoTime: time,
            ),
          ),
          ReelOverlayLayer(
            spec: OverlaySpec(
              output: output,
              caption: draft.caption.copyWith(text: due?.text ?? ''),
            ),
          ),
        ],
      ),
    );
  }
}
