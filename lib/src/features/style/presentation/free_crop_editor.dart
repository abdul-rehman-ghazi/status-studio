import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _handleSize = 28.0;

/// Shows the source frame with a crop rectangle the user drags to move and
/// resizes from its bottom-right corner (spec FR-6).
class FreeCropEditor extends StatefulWidget {
  const FreeCropEditor({
    super.key,
    required this.crop,
    required this.onChanged,
  });

  final FreeCropRect crop;
  final ValueChanged<FreeCropRect> onChanged;

  @override
  State<FreeCropEditor> createState() => _FreeCropEditorState();
}

class _FreeCropEditorState extends State<FreeCropEditor> {
  // Each drag is applied from where it started, so pointer events that land
  // between rebuilds are never lost.
  var _dragStartCrop = FreeCropRect.initial;
  var _dragOffset = Offset.zero;

  void _startDrag(DragStartDetails details) {
    _dragStartCrop = widget.crop;
    _dragOffset = Offset.zero;
  }

  void _move(DragUpdateDetails details, Size frame) {
    _dragOffset += details.delta;
    widget.onChanged(
      _dragStartCrop.moveBy(
        _dragOffset.dx / frame.width,
        _dragOffset.dy / frame.height,
      ),
    );
  }

  void _resize(DragUpdateDetails details, Size frame) {
    _dragOffset += details.delta;
    widget.onChanged(
      _dragStartCrop.resizeBy(
        _dragOffset.dx / frame.width,
        _dragOffset.dy / frame.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
            builder: (context, constraints) => _buildFrame(constraints.biggest),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: HintText('Drag to move. Drag the corner to resize.'),
            ),
            TextButton(
              onPressed: () => widget.onChanged(FreeCropRect.initial),
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFrame(Size frame) {
    final crop = widget.crop;
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.surface)),
        Positioned(
          left: crop.left * frame.width,
          top: crop.top * frame.height,
          width: crop.width * frame.width,
          height: crop.height * frame.height,
          child: Semantics(
            label: 'Crop area. Drag to move.',
            child: GestureDetector(
              onPanStart: _startDrag,
              onPanUpdate: (details) => _move(details, frame),
              child: _CropRectangle(
                handle: Semantics(
                  label: 'Resize crop. Drag the corner.',
                  child: GestureDetector(
                    onPanStart: _startDrag,
                    onPanUpdate: (details) => _resize(details, frame),
                    child: const _CornerHandle(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CropRectangle extends StatelessWidget {
  const _CropRectangle({required this.handle});

  final Widget handle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.accent, width: 2),
            ),
          ),
        ),
        Positioned(right: 0, bottom: 0, child: handle),
      ],
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _handleSize,
      height: _handleSize,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
      ),
      child: const Icon(
        Icons.open_in_full,
        size: 16,
        color: AppColors.onAccent,
      ),
    );
  }
}
