import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/presentation/scene_strip.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// The crop position picked on the scene strip: when it shows, how it is
/// reached, and Delete (spec FR-22).
class SelectedPositionCard extends StatelessWidget {
  const SelectedPositionCard({
    super.key,
    required this.span,
    required this.canDelete,
    required this.onArrival,
    required this.onDelete,
  });

  final CropSpan span;
  final bool canDelete;
  final ValueChanged<CropArrival> onArrival;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatClipTime(span.start)} – '
                  '${formatClipTime(span.end)} · '
                  '${sceneLengthLabel(span.length)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Delete position',
                onPressed: canDelete ? onDelete : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _arrival(),
        ],
      ),
    );
  }

  /// The first keyframe has nothing to arrive from (spec FR-22).
  Widget _arrival() {
    if (span.keyframeIndex == 0) {
      return const HintText('Starting position');
    }
    return Row(
      children: [
        const Expanded(child: HintText('Arrives by')),
        SegmentedButton<CropArrival>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: CropArrival.glide, label: Text('Glide')),
            ButtonSegment(value: CropArrival.cut, label: Text('Cut')),
          ],
          selected: {span.arrival},
          onSelectionChanged: (choice) => onArrival(choice.single),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
