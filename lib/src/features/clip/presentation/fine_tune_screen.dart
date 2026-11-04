import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/application/waveform_provider.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_warning.dart';
import 'package:status_studio/src/features/clip/domain/waveform.dart';
import 'package:status_studio/src/features/clip/presentation/clip_source_player.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/frame_controls.dart';
import 'package:status_studio/src/features/style/presentation/free_crop_editor.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Step 1 of Fine-tune: the clip's start and end, and how the video is
/// framed (spec FR-5, FR-6, FR-22).
class FineTuneScreen extends ConsumerStatefulWidget {
  const FineTuneScreen({super.key});

  @override
  ConsumerState<FineTuneScreen> createState() => _FineTuneScreenState();
}

class _FineTuneScreenState extends ConsumerState<FineTuneScreen> {
  final _playhead = ClipPlayhead();

  @override
  void dispose() {
    _playhead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final clip = draft.clip;
    final video = draft.video;
    if (clip == null || video == null) {
      throw StateError('Fine-tune opened without a video and a clip.');
    }
    final controller = ref.read(reelDraftProvider.notifier);
    return Scaffold(
      appBar: const FlowAppBar(
        title: 'Fine-tune · Video',
        stepLabel: 'Step 3 of 5',
      ),
      // The player stays put while the rest scrolls, so the lines can be
      // tapped with the video in view.
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: ClipSourcePlayer(
              video: video,
              clip: clip,
              playhead: _playhead,
            ),
          ),
          Expanded(child: _scrollingBody(draft, video, clip, controller)),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          onPressed: () => context.push(AppRoutes.lyrics),
          child: const Text('Next: lyrics'),
        ),
      ),
    );
  }

  Widget _scrollingBody(
    ReelDraft draft,
    SourceVideo video,
    ClipRange clip,
    ReelDraftController controller,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ClipSummary(clip: clip),
        if (isLongerThanStatusLimit(clip)) const _LongClipWarning(),
        const SizedBox(height: 16),
        _ClipWaveform(video: video, clip: clip),
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
        FrameControls(
          frame: draft.frame,
          sourceSize: previewSourceSize(ref, draft),
          onChanged: controller.updateFrame,
        ),
        if (draft.frame.preset == AspectPreset.free) ...[
          const SizedBox(height: 16),
          FreeCropEditor(
            crop: draft.frame.freeCrop,
            onChanged: (crop) =>
                controller.updateFrame(draft.frame.copyWith(freeCrop: crop)),
          ),
        ],
      ],
    );
  }
}

/// The waveform of the downloaded window; empty space until it's ready.
class _ClipWaveform extends ConsumerWidget {
  const _ClipWaveform({required this.video, required this.clip});

  final SourceVideo video;
  final ClipRange clip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref
        .watch(clipSourceProvider(video.videoId))
        .unwrapPrevious()
        .value;
    if (source == null) {
      return const SizedBox(height: 56);
    }
    final shown = waveformWindowFor(source, clip, video.duration);
    final peaks = ref
        .watch(waveformProvider((source: source, shown: shown)))
        .value;
    if (peaks == null) {
      return const SizedBox(height: 56);
    }
    return WaveformView(peaks: peaks, window: shown, clip: clip);
  }
}

class _LongClipWarning extends StatelessWidget {
  const _LongClipWarning();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Longer than 60 s. WhatsApp Status may cut it.',
              style: TextStyle(color: color),
            ),
          ),
        ],
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
