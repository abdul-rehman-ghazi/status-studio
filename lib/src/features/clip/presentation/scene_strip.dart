import 'package:flutter/material.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/playhead_redraw.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _stripHeight = 40.0;
const _blockGap = 2.0;

/// Below this width a block has no room for its length; the selected
/// position's card still says it.
const _minLabelledWidth = 34.0;

/// The crop's positions across the clip, each as wide as it lasts, with a
/// line at the playhead (spec FR-22). Always as wide as the screen allows:
/// it never scrolls.
class SceneStrip extends StatefulWidget {
  const SceneStrip({
    super.key,
    required this.spans,
    required this.clip,
    required this.selectedKeyframe,
    required this.playhead,
    required this.onSelected,
  });

  final List<CropSpan> spans;
  final ClipRange clip;
  final int selectedKeyframe;
  final ClipPlayhead playhead;
  final ValueChanged<CropSpan> onSelected;

  @override
  State<SceneStrip> createState() => _SceneStripState();
}

class _SceneStripState extends State<SceneStrip>
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
    return SizedBox(
      height: _stripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _blocks(constraints.maxWidth)),
            ?_playheadLine(constraints.maxWidth),
          ],
        ),
      ),
    );
  }

  Widget _blocks(double width) {
    final clipMicros = widget.clip.length.inMicroseconds;
    final gaps = _blockGap * (widget.spans.length - 1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          for (final (index, span) in widget.spans.indexed) ...[
            if (index > 0) const SizedBox(width: _blockGap),
            Expanded(
              flex: span.length.inMilliseconds.clamp(1, 1 << 30),
              child: _SceneBlock(
                span: span,
                selected: span.keyframeIndex == _selectedIndex,
                showLength:
                    (width - gaps) * span.length.inMicroseconds / clipMicros >=
                    _minLabelledWidth,
                onTap: () => widget.onSelected(span),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The selected keyframe may have no block (it lies outside the clip); the
  /// first block stands in for it then.
  int get _selectedIndex {
    final shown = widget.spans.any(
      (span) => span.keyframeIndex == widget.selectedKeyframe,
    );
    return shown ? widget.selectedKeyframe : widget.spans.first.keyframeIndex;
  }

  Widget? _playheadLine(double width) {
    if (!widget.playhead.isReady) {
      return null;
    }
    final clip = widget.clip;
    final position = widget.playhead.position;
    if (position < clip.start || position > clip.end) {
      return null;
    }
    final fraction =
        (position - clip.start).inMicroseconds / clip.length.inMicroseconds;
    return Positioned(
      left: width * fraction - 1,
      top: -3,
      bottom: -3,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          child: ColoredBox(color: context.palette.textPrimary),
        ),
      ),
    );
  }
}

class _SceneBlock extends StatelessWidget {
  const _SceneBlock({
    required this.span,
    required this.selected,
    required this.showLength,
    required this.onTap,
  });

  final CropSpan span;
  final bool selected;
  final bool showLength;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.palette.onAccent
        : context.palette.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Crop position, ${sceneLengthLabel(span.length)}',
      excludeSemantics: true,
      child: Material(
        color: selected ? context.palette.accent : context.palette.surface,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              if (span.arrival == CropArrival.cut && span.keyframeIndex > 0)
                Positioned(
                  left: 3,
                  top: 2,
                  child: Icon(Icons.content_cut, size: 10, color: foreground),
                ),
              if (showLength)
                Center(
                  child: Text(
                    sceneLengthLabel(span.length),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "5 s" for whole seconds and up; "0.4 s" below one second.
String sceneLengthLabel(Duration length) {
  final seconds = length.inMilliseconds / Duration.millisecondsPerSecond;
  if (seconds < 1) {
    return '${seconds.toStringAsFixed(1)} s';
  }
  return '${seconds.round()} s';
}
