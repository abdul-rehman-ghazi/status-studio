import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/option_row.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// Size, fill and keep-in-view choices (spec FR-6), on Fine-tune · Video.
class FrameControls extends StatelessWidget {
  const FrameControls({
    super.key,
    required this.frame,
    required this.sourceSize,
    required this.onChanged,
  });

  final FrameSettings frame;

  /// The clip's frame size, for the free crop's output size.
  final OutputSize sourceSize;
  final ValueChanged<FrameSettings> onChanged;

  static const _presetHints = {
    AspectPreset.story9x16: 'Status, Reels, TikTok, Shorts',
    AspectPreset.portrait4x5: 'Instagram and Facebook posts',
    AspectPreset.square1x1: 'Square posts',
    AspectPreset.landscape16x9: 'Original frame, no crop',
    AspectPreset.free: 'Your own crop',
  };

  @override
  Widget build(BuildContext context) {
    final output = outputSizeFor(frame, sourceSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Size'),
        OptionRow<AspectPreset>(
          options: [
            for (final preset in AspectPreset.values)
              (value: preset, label: preset.label),
          ],
          selected: frame.preset,
          onSelected: (preset) => onChanged(frame.copyWith(preset: preset)),
        ),
        const SizedBox(height: 8),
        HintText('${_presetHints[frame.preset]} · $output'),
        if (frame.offersFill) ...[
          const SizedBox(height: 20),
          const SectionLabel('Fill'),
          OptionRow<FillMode>(
            options: const [
              (value: FillMode.crop, label: 'Crop to fill'),
              (value: FillMode.blur, label: 'Blur background'),
            ],
            selected: frame.fill,
            onSelected: (fill) => onChanged(frame.copyWith(fill: fill)),
          ),
        ],
        if (frame.offersFocus) ...[
          const SizedBox(height: 20),
          const SectionLabel('Keep in view'),
          OptionRow<CropFocus>(
            options: const [
              (value: CropFocus.left, label: 'Left'),
              (value: CropFocus.center, label: 'Center'),
              (value: CropFocus.right, label: 'Right'),
            ],
            selected: frame.focus,
            onSelected: (focus) => onChanged(frame.withFocus(focus)),
          ),
        ],
      ],
    );
  }
}
