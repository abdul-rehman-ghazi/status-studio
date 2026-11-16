import 'package:flutter/material.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/playhead_redraw.dart';

/// Dims the picture with "Not in the clip" (spec FR-5, FR-39).
class NotInClipShade extends StatelessWidget {
  const NotInClipShade({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black54,
        // At the top: the middle belongs to Play (M76).
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Not in the clip',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// [NotInClipShade] while [playhead] is outside [clip], following the
/// playhead every frame so the shade comes and goes on the clip's edges.
class OutsideClipShade extends StatefulWidget {
  const OutsideClipShade({
    super.key,
    required this.playhead,
    required this.clip,
  });

  final ClipPlayhead playhead;

  /// In video time.
  final ClipRange clip;

  @override
  State<OutsideClipShade> createState() => _OutsideClipShadeState();
}

class _OutsideClipShadeState extends State<OutsideClipShade>
    with SingleTickerProviderStateMixin {
  late final PlayheadRedraw _redraw;
  var _isInside = true;

  @override
  void initState() {
    super.initState();
    _redraw = PlayheadRedraw(
      vsync: this,
      playhead: widget.playhead,
      isMounted: () => mounted,
      redraw: _followPlayhead,
    );
  }

  @override
  void dispose() {
    _redraw.dispose();
    super.dispose();
  }

  bool _playheadIsInside() {
    final position = widget.playhead.position;
    return position >= widget.clip.start && position < widget.clip.end;
  }

  // Rebuilds only when the playhead crosses an edge, not every frame.
  void _followPlayhead() {
    final isInside = _playheadIsInside();
    if (isInside != _isInside) {
      setState(() => _isInside = isInside);
    }
  }

  @override
  Widget build(BuildContext context) {
    _isInside = _playheadIsInside();
    return _isInside ? const SizedBox.shrink() : const NotInClipShade();
  }
}
