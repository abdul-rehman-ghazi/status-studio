import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';

/// The Follow the person button, or how far a run has got with a Cancel
/// (spec FR-23).
class FollowSubjectSection extends StatelessWidget {
  const FollowSubjectSection({
    super.key,
    required this.state,
    required this.canStart,
    required this.onStart,
    required this.onCancel,
  });

  final FollowState state;

  /// False until the clip has downloaded.
  final bool canStart;
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
        FollowChoosing() => _StartButton(canStart: false, onStart: onStart),
        _ => _StartButton(canStart: canStart, onStart: onStart),
      },
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.canStart, required this.onStart});

  final bool canStart;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: canStart ? onStart : null,
          icon: const Icon(Icons.person_search_outlined),
          label: const Text('Follow the person'),
        ),
        const SizedBox(height: 6),
        const HintText('Runs on your phone; nothing is uploaded.'),
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
