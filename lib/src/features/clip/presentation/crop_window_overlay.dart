import 'package:flutter/material.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/presentation/playhead_redraw.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Extra reach around the window's outline that still starts a drag (spec
/// FR-22): a thumb is wider than a 2 dp line.
const _touchMargin = 24.0;

/// The crop window drawn over the video where it is at the playhead, with
/// the rest dimmed. While [editable], it can be dragged: it follows the
/// finger, and one keyframe is written when the finger lifts (spec FR-22).
class CropWindowOverlay extends StatefulWidget {
  const CropWindowOverlay({
    super.key,
    required this.frame,
    required this.sourceSize,
    required this.playhead,
    required this.editable,
    required this.onMoved,
  });

  final FrameSettings frame;
  final OutputSize sourceSize;
  final ClipPlayhead playhead;
  final bool editable;

  /// The anchor chosen by a drag, and the playhead time where it started.
  final void Function(Duration videoTime, CropAnchor anchor) onMoved;

  @override
  State<CropWindowOverlay> createState() => _CropWindowOverlayState();
}

class _CropWindowOverlayState extends State<CropWindowOverlay>
    with SingleTickerProviderStateMixin {
  late final PlayheadRedraw _redraw;
  CropAnchor? _dragAnchor;
  var _dragStartTime = Duration.zero;

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

  CropAnchor get _anchorNow {
    final frame = widget.frame;
    return frame.cropPath.anchorAt(
      widget.playhead.position,
      base: baseAnchorFor(frame),
    );
  }

  PixelRect get _window => cropRectForAnchor(
    widget.frame,
    widget.sourceSize,
    _dragAnchor ?? _anchorNow,
  );

  void _startDrag(DragStartDetails details) {
    _dragStartTime = widget.playhead.position;
    setState(() => _dragAnchor = _anchorNow);
  }

  void _drag(DragUpdateDetails details, Size shown) {
    final start = _dragAnchor;
    if (start == null) {
      return;
    }
    final source = widget.sourceSize;
    final window = cropRectForAnchor(widget.frame, source, start);
    final roomX = (source.width - window.width) / source.width * shown.width;
    final roomY =
        (source.height - window.height) / source.height * shown.height;
    setState(() {
      _dragAnchor = CropAnchor(
        x: roomX > 0 ? start.x + details.delta.dx / roomX : start.x,
        y: roomY > 0 ? start.y + details.delta.dy / roomY : start.y,
      ).clamped();
    });
  }

  void _endDrag(DragEndDetails details) {
    final anchor = _dragAnchor;
    setState(() => _dragAnchor = null);
    if (anchor != null) {
      widget.onMoved(_dragStartTime, anchor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = constraints.biggest;
        final source = widget.sourceSize;
        final window = _window;
        final rect = Rect.fromLTWH(
          window.x / source.width * shown.width,
          window.y / source.height * shown.height,
          window.width / source.width * shown.width,
          window.height / source.height * shown.height,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DimOutsidePainter(rect)),
              ),
            ),
            if (widget.editable)
              Positioned.fromRect(
                rect: rect.inflate(_touchMargin),
                child: Semantics(
                  label: 'Crop window. Drag to move it.',
                  child: GestureDetector(
                    key: const ValueKey('crop-window'),
                    behavior: HitTestBehavior.translucent,
                    onPanStart: _startDrag,
                    onPanUpdate: (details) => _drag(details, shown),
                    onPanEnd: _endDrag,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DimOutsidePainter extends CustomPainter {
  const _DimOutsidePainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(window),
    );
    canvas
      ..drawPath(outside, Paint()..color = Colors.black54)
      ..drawRect(
        window,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_DimOutsidePainter oldDelegate) =>
      oldDelegate.window != window;
}
