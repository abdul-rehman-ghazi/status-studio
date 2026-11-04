import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/application/waveform_provider.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_warning.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/clip/domain/waveform.dart';
import 'package:status_studio/src/features/clip/presentation/clip_lines_list.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class FineTuneScreen extends ConsumerStatefulWidget {
  const FineTuneScreen({super.key});

  @override
  ConsumerState<FineTuneScreen> createState() => _FineTuneScreenState();
}

class _FineTuneScreenState extends ConsumerState<FineTuneScreen> {
  static const _saveDelay = Duration(seconds: 1);

  final _playhead = ClipPlayhead();
  late final ScriptEditingService _scriptEditing;
  Timer? _saveTimer;
  Future<void> Function()? _pendingSave;

  @override
  void initState() {
    super.initState();
    // Read now: dispose saves a pending edit and can't use ref.
    _scriptEditing = ref.read(scriptEditingServiceProvider);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_savePending());
    _playhead.dispose();
    super.dispose();
  }

  /// Saves after a pause in editing, so a run of taps is one write (FR-21).
  void _scheduleSave() {
    final draft = ref.read(reelDraftProvider);
    final video = draft.video;
    final edited = draft.transcript;
    if (video == null || edited == null) {
      return;
    }
    _pendingSave = () =>
        _scriptEditing.saveCorrected(video, draft.language, edited);
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_savePending()));
  }

  Future<void> _savePending() async {
    final save = _pendingSave;
    _pendingSave = null;
    if (save == null) {
      return;
    }
    try {
      await save();
    } on Object {
      // The edits are still in the draft and reach the reel; a full disk
      // must not interrupt timing lines.
    }
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
      appBar: const FlowAppBar(title: 'Fine-tune', stepLabel: 'Step 3 of 4'),
      // The player stays put while the rest scrolls, so the lines can be
      // tapped with the video in view.
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _SourcePreview(
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
          onPressed: () => context.push(AppRoutes.style),
          child: const Text('Next: frame & caption'),
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
        const SectionLabel('Lines'),
        const HintText(
          'Tap a line to jump to it. While the clip plays, tap a line '
          'when it starts to time it.',
        ),
        ClipLinesList(
          script: draft.pickedScript,
          window: clipWindowFor(clip, video.duration),
          playhead: _playhead,
          onEdited: _scheduleSave,
        ),
      ],
    );
  }
}

/// The clip player once the clip's window is downloaded (FR-15); until
/// then, how far the download has got.
class _SourcePreview extends ConsumerStatefulWidget {
  const _SourcePreview({
    required this.video,
    required this.clip,
    required this.playhead,
  });

  final SourceVideo video;
  final ClipRange clip;
  final ClipPlayhead playhead;

  @override
  ConsumerState<_SourcePreview> createState() => _SourcePreviewState();
}

class _SourcePreviewState extends ConsumerState<_SourcePreview> {
  @override
  void initState() {
    super.initState();
    // Providers can't change during build, so the first download waits for
    // the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prepareFor(widget.clip);
      }
    });
  }

  @override
  void didUpdateWidget(_SourcePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clip != oldWidget.clip) {
      // A nudge past the downloaded window needs a new one; inside it this
      // does nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _prepareFor(widget.clip);
        }
      });
    }
  }

  void _prepareFor(ClipRange clip) {
    unawaited(
      ref
          .read(clipSourceProvider(widget.video.videoId).notifier)
          .prepareFor(widget.video, clip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoId = widget.video.videoId;
    // unwrapPrevious: a new window or a retry shows progress, not the
    // earlier file or failure.
    final source = ref.watch(clipSourceProvider(videoId)).unwrapPrevious();
    if (source.value case final clipSource?) {
      return ClipPlayer(
        key: ValueKey(clipSource.file.path),
        source: clipSource,
        clip: widget.clip,
        playhead: widget.playhead,
      );
    }
    if (source.error case final error?) {
      return _PreviewMessage(text: errorMessageFor(error));
    }
    final fraction = ref.watch(clipSourceProgressProvider(videoId));
    final percent = (fraction * 100).round();
    return _PreviewMessage(text: 'Downloading clip… $percent %');
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: HintText(text)),
      ),
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
