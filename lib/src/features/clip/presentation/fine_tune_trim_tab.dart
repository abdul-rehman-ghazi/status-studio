import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/application/waveform_provider.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/waveform.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Fine-tune · Video's Trim tab: the clip's length, its waveform, and its
/// start and end with the nudges (spec FR-5).
class FineTuneTrimTab extends ConsumerWidget {
  const FineTuneTrimTab({
    super.key,
    required this.video,
    required this.clip,
    required this.playhead,
  });

  final SourceVideo video;
  final ClipRange clip;
  final ClipPlayhead playhead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(reelDraftProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ClipSummary(clip: clip),
        // if (isLongerThanStatusLimit(clip)) const _LongClipWarning(),
        const SizedBox(height: 16),
        _ClipWaveform(video: video, clip: clip),
        const SizedBox(height: 16),
        // _WholeVideoBar(clip: clip, videoDuration: video.duration),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _NudgeCard(
                edge: _ClipEdge.start,
                time: clip.start,
                onNudge: controller.nudgeClipStart,
                onSetToPlayhead: () =>
                    _setToPlayhead(controller.setClipStartAt),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NudgeCard(
                edge: _ClipEdge.end,
                time: clip.end,
                onNudge: controller.nudgeClipEnd,
                onSetToPlayhead: () => _setToPlayhead(controller.setClipEndAt),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const HintText(
          'Tap a time to set it to where the video is now, or nudge it.',
        ),
        if (video.pictureStart > Duration.zero)
          _LatePictureHint(pictureStart: video.pictureStart),
        const SizedBox(height: 16),
        const _FadeSwitch(),
        // iOS's audio mix can't go above full volume (spec FR-42).
        if (defaultTargetPlatform == TargetPlatform.android)
          const _LouderSoundSwitch(),
      ],
    );
  }

  /// Tapping a clip time sets it to where the video is now (spec FR-5).
  void _setToPlayhead(void Function(Duration videoTime) setEdge) {
    if (playhead.isReady) {
      setEdge(playhead.position);
    }
  }
}

/// A video whose picture starts after its sound can't be clipped from
/// before the picture (spec FR-5, M41).
class _LatePictureHint extends StatelessWidget {
  const _LatePictureHint({required this.pictureStart});

  final Duration pictureStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: HintText(
        'The picture starts at ${formatClipTime(pictureStart)}, '
        "so the clip can't start earlier.",
      ),
    );
  }
}

/// Fade in from black and out to black (spec FR-33).
class _FadeSwitch extends ConsumerWidget {
  const _FadeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fading = ref.watch(reelDraftProvider.select((d) => d.fadeEnds));
    final controller = ref.read(reelDraftProvider.notifier);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Fade in and out'),
      subtitle: const Text(
        'The picture fades in from black and out to black. '
        "The sound doesn't change.",
      ),
      value: fading,
      onChanged: (on) =>
          on ? controller.fadeEnds() : controller.stopFadingEnds(),
    );
  }
}

/// Raises quiet sound to a steady level at export (spec FR-42).
class _LouderSoundSwitch extends ConsumerWidget {
  const _LouderSoundSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final louder = ref.watch(reelDraftProvider.select((d) => d.louderSound));
    final controller = ref.read(reelDraftProvider.notifier);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Make the sound louder'),
      subtitle: const Text(
        'Quiet sound is raised to a steady level, and loud peaks are held '
        'down. You hear it in the saved reel.',
      ),
      value: louder,
      onChanged: (on) =>
          on ? controller.makeSoundLouder() : controller.keepSoundAsIs(),
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
          style: textTheme.titleMedium?.copyWith(color: context.palette.accent),
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
                  Positioned.fill(
                    child: ColoredBox(color: context.palette.surface),
                  ),
                  Positioned(
                    left: constraints.maxWidth * startFraction,
                    width: constraints.maxWidth * lengthFraction,
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(color: context.palette.accent),
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
    required this.onSetToPlayhead,
  });

  final _ClipEdge edge;
  final Duration time;
  final ValueChanged<Duration> onNudge;
  final VoidCallback onSetToPlayhead;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          HintText(edge.label),
          Semantics(
            label: 'Set ${edge.label.toLowerCase()} to the playhead',
            button: true,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onSetToPlayhead,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  formatClipTime(time),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
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
