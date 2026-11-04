import 'package:flutter/material.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// One chip per crop keyframe, and, for the selected one, how it is reached
/// and a Delete (spec FR-22). Keyframes outside the clip are dimmed.
class CropKeyframeChips extends StatelessWidget {
  const CropKeyframeChips({
    super.key,
    required this.path,
    required this.clip,
    required this.selected,
    required this.onSelected,
    required this.onArrival,
    required this.onDelete,
  });

  final CropPath path;
  final ClipRange clip;
  final int selected;
  final ValueChanged<int> onSelected;
  final void Function(int index, CropArrival arrival) onArrival;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final keyframes = path.keyframes;
    final selectedIndex = selected.clamp(0, keyframes.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (index, keyframe) in keyframes.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                  child: Opacity(
                    opacity: _isInClip(keyframe) ? 1 : 0.45,
                    child: ChoiceChip(
                      label: Text(formatClipTime(keyframe.time)),
                      selected: index == selectedIndex,
                      onSelected: (_) => onSelected(index),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _SelectedKeyframe(
          index: selectedIndex,
          keyframe: keyframes[selectedIndex],
          canDelete: keyframes.length > 1,
          onArrival: onArrival,
          onDelete: onDelete,
        ),
      ],
    );
  }

  bool _isInClip(CropKeyframe keyframe) =>
      keyframe.time >= clip.start && keyframe.time <= clip.end;
}

class _SelectedKeyframe extends StatelessWidget {
  const _SelectedKeyframe({
    required this.index,
    required this.keyframe,
    required this.canDelete,
    required this.onArrival,
    required this.onDelete,
  });

  final int index;
  final CropKeyframe keyframe;
  final bool canDelete;
  final void Function(int index, CropArrival arrival) onArrival;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The first keyframe has nothing to arrive from.
        if (index > 0)
          SegmentedButton<CropArrival>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: CropArrival.glide, label: Text('Glide')),
              ButtonSegment(value: CropArrival.cut, label: Text('Cut')),
            ],
            selected: {keyframe.arrival},
            onSelectionChanged: (choice) => onArrival(index, choice.single),
          )
        else
          const Text(
            'Starting position',
            style: TextStyle(color: AppColors.textMuted),
          ),
        const Spacer(),
        IconButton(
          tooltip: 'Delete keyframe',
          onPressed: canDelete ? () => onDelete(index) : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}
