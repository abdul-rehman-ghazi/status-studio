import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';

/// New position here and Follow the person side by side, or how far a
/// Follow run has got with a Cancel (spec FR-22, FR-27).
class FollowSubjectSection extends StatelessWidget {
  const FollowSubjectSection({
    super.key,
    required this.state,
    required this.canStart,
    required this.onAddPosition,
    required this.onStart,
    required this.onCancel,
  });

  final FollowState state;

  /// False until the clip has downloaded.
  final bool canStart;
  final VoidCallback onAddPosition;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: switch (state) {
        FollowRunning(:final fraction) => _Progress(
          fraction: fraction,
          onCancel: onCancel,
        ),
        // The question is open in a sheet; the button comes back with its end.
        FollowChoosing() => _Buttons(
          canStart: false,
          onAddPosition: onAddPosition,
          onStart: onStart,
        ),
        _ => _Buttons(
          canStart: canStart,
          onAddPosition: onAddPosition,
          onStart: onStart,
        ),
      },
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.canStart,
    required this.onAddPosition,
    required this.onStart,
  });

  final bool canStart;
  final VoidCallback onAddPosition;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddPosition,
                icon: const Icon(Icons.add),
                label: const Text(
                  'New position here',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canStart ? onStart : null,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text(
                  'Follow the person',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const HintText(
          'Drag the crop on the video to move this position. Follow the '
          'person runs on your phone; nothing is uploaded.',
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.fraction, required this.onCancel});

  final double fraction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // Sampling the frames has no progress to show; the percent starts with
    // the first look at a frame.
    final measured = fraction > 0;
    final percent = (fraction * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                measured
                    ? 'Finding the person… $percent %'
                    : 'Finding the person…',
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
        LinearProgressIndicator(value: measured ? fraction : null),
      ],
    );
  }
}
