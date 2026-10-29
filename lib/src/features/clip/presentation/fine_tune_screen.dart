import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class FineTuneScreen extends ConsumerWidget {
  const FineTuneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reelDraftProvider);
    final clip = draft.clip;
    final video = draft.video;
    if (clip == null || video == null) {
      throw StateError('Fine-tune opened without a video and a clip.');
    }
    final controller = ref.read(reelDraftProvider.notifier);
    return Scaffold(
      appBar: const FlowAppBar(title: 'Fine-tune', stepLabel: 'Step 3 of 4'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _PreviewPlaceholder(),
          const SizedBox(height: 16),
          _ClipSummary(clip: clip),
          const SizedBox(height: 16),
          _WholeVideoBar(clip: clip, videoDuration: video.duration),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _NudgeCard(
                  edge: _ClipEdge.start,
                  time: clip.start,
                  onNudge: controller.nudgeClipStart,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NudgeCard(
                  edge: _ClipEdge.end,
                  time: clip.end,
                  onNudge: controller.nudgeClipEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('Lines in this clip'),
          for (final line in _selectedLines(draft)) _ClipLine(line: line),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          onPressed: () => context.push(AppRoutes.style),
          child: const Text('Next: frame & caption'),
        ),
      ),
    );
  }
}

List<TranscriptLine> _selectedLines(ReelDraft draft) {
  final lines = draft.transcript?.lines ?? const <TranscriptLine>[];
  return switch (draft.selection) {
    RangeSelected(:final start, :final end) => lines.sublist(start, end + 1),
    _ => const [],
  };
}

/// Stands in for the clip player until M2 brings real video.
class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.play_circle_outline,
          size: 48,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _ClipSummary extends StatelessWidget {
  const _ClipSummary({required this.clip});

  final ClipRange clip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${formatClipTime(clip.start)} – ${formatClipTime(clip.end)}',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          formatSeconds(clip.length),
          style: textTheme.titleMedium?.copyWith(color: AppColors.accent),
        ),
      ],
    );
  }
}

class _WholeVideoBar extends StatelessWidget {
  const _WholeVideoBar({required this.clip, required this.videoDuration});

  final ClipRange clip;
  final Duration videoDuration;

  @override
  Widget build(BuildContext context) {
    final total = videoDuration.inMilliseconds;
    final startFraction = clip.start.inMilliseconds / total;
    final lengthFraction = clip.length.inMilliseconds / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: HintText('Whole video')),
            HintText(formatTimestamp(videoDuration)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: AppColors.surface),
                  ),
                  Positioned(
                    left: constraints.maxWidth * startFraction,
                    width: constraints.maxWidth * lengthFraction,
                    top: 0,
                    bottom: 0,
                    child: const ColoredBox(color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _ClipEdge {
  start('Start'),
  end('End');

  const _ClipEdge(this.label);

  final String label;
}

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({
    required this.edge,
    required this.time,
    required this.onNudge,
  });

  final _ClipEdge edge;
  final Duration time;
  final ValueChanged<Duration> onNudge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          HintText(edge.label),
          Text(
            formatClipTime(time),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NudgeButton(
                  label: '${edge.label} half a second earlier',
                  text: '−0.5s',
                  onPressed: () => onNudge(-ClipRange.nudgeStep),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NudgeButton(
                  label: '${edge.label} half a second later',
                  text: '+0.5s',
                  onPressed: () => onNudge(ClipRange.nudgeStep),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.label,
    required this.text,
    required this.onPressed,
  });

  final String label;
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }
}

class _ClipLine extends StatelessWidget {
  const _ClipLine({required this.line});

  final TranscriptLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: HintText(formatTimestamp(line.start)),
          ),
          const SizedBox(width: 12),
          Expanded(child: ScriptText(line.text)),
        ],
      ),
    );
  }
}
