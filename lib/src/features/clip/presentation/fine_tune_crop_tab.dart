import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/presentation/follow_subject_section.dart';
import 'package:status_studio/src/features/clip/presentation/scene_strip.dart';
import 'package:status_studio/src/features/clip/presentation/selected_position_card.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/frame_controls.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';

/// What the Crop tab asks the screen to do: the screen owns the selection,
/// the playhead and the Follow sheet.
@immutable
class CropTabActions {
  const CropTabActions({
    required this.onSpanSelected,
    required this.onMovingChanged,
    required this.onAddPosition,
    required this.onFollow,
  });

  final ValueChanged<CropSpan> onSpanSelected;
  final ValueChanged<bool> onMovingChanged;
  final VoidCallback onAddPosition;
  final VoidCallback onFollow;
}

/// Fine-tune · Video's Crop tab: size and fill, and everything about the
/// crop that moves at each scene in one place (spec FR-6, FR-22, FR-27).
class FineTuneCropTab extends ConsumerWidget {
  const FineTuneCropTab({
    super.key,
    required this.selectedKeyframe,
    required this.playhead,
    required this.actions,
  });

  final int selectedKeyframe;
  final ClipPlayhead playhead;
  final CropTabActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reelDraftProvider);
    final controller = ref.read(reelDraftProvider.notifier);
    final sourceSize = previewSourceSize(ref, draft);
    final canMove = canMoveCrop(draft.frame, sourceSize);
    final moving = !draft.frame.cropPath.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FrameControls(
          frame: draft.frame,
          sourceSize: sourceSize,
          onChanged: controller.updateFrame,
        ),
        if (draft.frame.preset == AspectPreset.free)
          _FreeCropHint(
            onReset: () => controller.resizeFreeCrop(FreeCropRect.initial),
          ),
        // Kept while moving, so a crop that can no longer move (Blur, 16:9)
        // can still be turned off.
        if (canMove || moving)
          _MovingCropSwitch(moving: moving, onChanged: actions.onMovingChanged),
        if (canMove && moving) ..._scenes(ref, draft),
      ],
    );
  }

  List<Widget> _scenes(WidgetRef ref, ReelDraft draft) {
    final clip = draft.clip!;
    final path = draft.frame.cropPath;
    final spans = path.spansIn(clip);
    final selected = spans.firstWhere(
      (span) => span.keyframeIndex == selectedKeyframe,
      orElse: () => spans.first,
    );
    final controller = ref.read(reelDraftProvider.notifier);
    final video = draft.video!;
    return [
      const SizedBox(height: 8),
      SceneStrip(
        spans: spans,
        clip: clip,
        selectedKeyframe: selected.keyframeIndex,
        playhead: playhead,
        onSelected: actions.onSpanSelected,
      ),
      SelectedPositionCard(
        span: selected,
        canDelete: path.keyframes.length > 1,
        onArrival: (arrival) =>
            controller.setCropArrival(selected.keyframeIndex, arrival),
        onDelete: () => controller.removeCropKeyframe(selected.keyframeIndex),
      ),
      FollowSubjectSection(
        state: ref.watch(followSubjectProvider),
        canStart: ref.watch(clipSourceProvider(video.videoId)).value != null,
        onAddPosition: actions.onAddPosition,
        onStart: actions.onFollow,
        onCancel: ref.read(followSubjectProvider.notifier).cancel,
      ),
    ];
  }
}

class _MovingCropSwitch extends StatelessWidget {
  const _MovingCropSwitch({required this.moving, required this.onChanged});

  final bool moving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Move the crop at each scene'),
        subtitle: const HintText(
          'Each block below is one place for the crop, as long as it lasts. '
          'It glides or cuts to each new place.',
        ),
        value: moving,
        onChanged: onChanged,
      ),
    );
  }
}

/// The free crop is edited on the player (spec FR-6); this says how.
class _FreeCropHint extends StatelessWidget {
  const _FreeCropHint({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: HintText(
            'Drag the crop on the video to move it. Drag its corner to resize.',
          ),
        ),
        TextButton(onPressed: onReset, child: const Text('Reset')),
      ],
    );
  }
}
