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

const _handleSize = 28.0;

/// The crop window drawn over the video where it is at the playhead, with
/// the rest dimmed. While [editable], it can be dragged: it follows the
/// finger, and [onMoved] is called once when the finger lifts (spec FR-22).
/// With [onResized], a free crop also gets a corner to resize it (FR-6).
class CropWindowOverlay extends StatefulWidget {
  const CropWindowOverlay({
    super.key,
    required this.frame,
    required this.sourceSize,
    required this.playhead,
    required this.editable,
    required this.onMoved,
    this.onResized,
  });

  final FrameSettings frame;
  final OutputSize sourceSize;
  final ClipPlayhead playhead;
  final bool editable;

  /// The anchor chosen by a drag, and the playhead time where it started.
  final void Function(Duration videoTime, CropAnchor anchor) onMoved;

  /// The free crop resized from its bottom-right corner.
  final ValueChanged<FreeCropRect>? onResized;

  @override
  State<CropWindowOverlay> createState() => _CropWindowOverlayState();
}

class _CropWindowOverlayState extends State<CropWindowOverlay>
    with SingleTickerProviderStateMixin {
  late final PlayheadRedraw _redraw;
  CropAnchor? _dragAnchor;
  var _dragStartTime = Duration.zero;

  // A resize is applied from where it started, so pointer events that land
  // between rebuilds are never lost.
  var _resizeStartCrop = FreeCropRect.initial;
  var _resizeOffset = Offset.zero;

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

  void _startResize(DragStartDetails details) {
    _resizeStartCrop = widget.frame.freeCrop;
    _resizeOffset = Offset.zero;
  }

  void _resize(
    DragUpdateDetails details,
    Size shown,
    ValueChanged<FreeCropRect> onResized,
  ) {
    _resizeOffset += details.delta;
    onResized(
      _resizeStartCrop.resizeBy(
        _resizeOffset.dx / shown.width,
        _resizeOffset.dy / shown.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = constraints.biggest;
        final source = widget.sourceSize;
        final window = _window;
        final onResized = widget.onResized;
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
                    onPanCancel: () => setState(() => _dragAnchor = null),
                  ),
                ),
              ),
            if (onResized != null && widget.frame.preset == AspectPreset.free)
              Positioned(
                left: rect.right - _handleSize,
                top: rect.bottom - _handleSize,
                child: Semantics(
                  label: 'Resize crop. Drag the corner.',
                  child: GestureDetector(
                    key: const ValueKey('free-crop-corner'),
                    onPanStart: _startResize,
                    onPanUpdate: (details) =>
                        _resize(details, shown, onResized),
                    child: const _CornerHandle(),
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
          ..color = PictureMarkColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_DimOutsidePainter oldDelegate) =>
      oldDelegate.window != window;
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _handleSize,
      height: _handleSize,
      decoration: const BoxDecoration(
        color: PictureMarkColors.accent,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
      ),
      child: const Icon(
        Icons.open_in_full,
        size: 16,
        color: PictureMarkColors.onAccent,
      ),
    );
  }
}
