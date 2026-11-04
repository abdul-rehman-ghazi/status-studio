import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
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
import 'package:status_studio/src/features/clip/presentation/crop_keyframe_chips.dart';
import 'package:status_studio/src/features/clip/presentation/crop_window_overlay.dart';
import 'package:status_studio/src/features/clip/presentation/follow_subject_section.dart';
import 'package:status_studio/src/features/clip/presentation/waveform_view.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
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
  var _selectedKeyframe = 0;

  /// True while Lyrics is open: two players over one clip can be more than a
  /// phone's hardware decoders allow, so this step lets go of its own.
  var _playerReleased = false;

  static const _keepDelay = Duration(seconds: 1);

  late final FineTuneDraftSaver _saver;
  late final AppLifecycleListener _lifecycle;
  late ReelDraft _latestDraft;
  Timer? _keepTimer;

  @override
  void initState() {
    super.initState();
    // Read now: dispose keeps the latest work and can't use ref.
    _saver = ref.read(fineTuneDraftSaverProvider);
    _latestDraft = ref.read(reelDraftProvider);
    // This step stays open under Lyrics, Style and Export, so it sees every
    // change to the reel (spec FR-24).
    ref.listenManual(reelDraftProvider, (_, next) {
      _latestDraft = next;
      _keepTimer?.cancel();
      _keepTimer = Timer(_keepDelay, _keepNow);
    });
    _lifecycle = AppLifecycleListener(onHide: _keepNow);
  }

  @override
  void dispose() {
    _keepTimer?.cancel();
    _lifecycle.dispose();
    _keepNow();
    _playhead.dispose();
    super.dispose();
  }

  void _keepNow() => unawaited(_saver.save(_latestDraft));

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final clip = draft.clip;
    final video = draft.video;
    if (clip == null || video == null) {
      throw StateError('Fine-tune opened without a video and a clip.');
    }
    final controller = ref.read(reelDraftProvider.notifier);
    final sourceSize = previewSourceSize(ref, draft);
    final path = draft.frame.cropPath;
    final canMove = canMoveCrop(draft.frame, sourceSize);
    final follow = ref.watch(followSubjectProvider);
    ref.listen(followSubjectProvider, _showHowFollowEnded);
    return Scaffold(
      appBar: const FlowAppBar(
        title: 'Fine-tune · Video',
        stepLabel: 'Step 3 of 5',
      ),
      // The player and the crop keyframes stay put while the rest scrolls,
      // so the crop can be moved with the video in view.
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _playerReleased
                ? const ClipPlayerPlaceholder()
                : ClipSourcePlayer(
                    video: video,
                    clip: clip,
                    playhead: _playhead,
                    videoOverlay: canMove
                        ? CropWindowOverlay(
                            frame: draft.frame,
                            sourceSize: sourceSize,
                            playhead: _playhead,
                            editable: !path.isEmpty,
                            onMoved: (time, anchor) =>
                                _moveCropTo(controller, time, anchor),
                          )
                        : null,
                  ),
          ),
          if (!path.isEmpty && canMove)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CropKeyframeChips(
                path: path,
                clip: clip,
                selected: _selectedKeyframe,
                onSelected: (index) => _selectKeyframe(path, index),
                onArrival: controller.setCropArrival,
                onDelete: controller.removeCropKeyframe,
              ),
            ),
          Expanded(
            child: _scrollingBody(
              draft,
              video,
              clip,
              controller,
              sourceSize,
              follow,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          onPressed: _openLyrics,
          child: const Text('Next: lyrics'),
        ),
      ),
    );
  }

  /// Asks first when the user has keyframes of their own to lose.
  Future<void> _follow() async {
    final keyframes = ref.read(reelDraftProvider).frame.cropPath.keyframes;
    if (keyframes.length > 1 && !await _confirmReplacingKeyframes()) {
      return;
    }
    if (mounted) {
      unawaited(ref.read(followSubjectProvider.notifier).start());
    }
  }

  Future<bool> _confirmReplacingKeyframes() async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace your crop keyframes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return replace ?? false;
  }

  /// Says how a run ended (spec FR-23), then clears it.
  void _showHowFollowEnded(FollowState? before, FollowState after) {
    final message = switch (after) {
      FollowDone(:final keyframeCount) =>
        'The crop follows the person ($keyframeCount '
            '${keyframeCount == 1 ? 'keyframe' : 'keyframes'}). '
            'Drag or tap a chip to adjust.',
      FollowNoSubject() => errorMessageFor(const NoSubjectFoundException()),
      FollowFailed() => errorMessageFor(const FollowFailedException('')),
      _ => null,
    };
    if (message == null) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (after is FollowDone) {
      _selectFirstKeyframeAtTheStart();
    }
    ref.read(followSubjectProvider.notifier).reset();
  }

  void _selectFirstKeyframeAtTheStart() {
    setState(() => _selectedKeyframe = 0);
    final clip = ref.read(reelDraftProvider).clip;
    if (clip != null && _playhead.isReady) {
      unawaited(_playhead.seekTo(clip.start));
    }
  }

  /// Lyrics starts its own player only once this step's is gone, and this
  /// step makes its player again only once Lyrics has slid away: never two
  /// decoders at a time (spec FR-22).
  Future<void> _openLyrics() async {
    ref.read(followSubjectProvider.notifier).cancel();
    setState(() => _playerReleased = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    await context.push(AppRoutes.lyrics);
    await _untilDismissed(covered);
    if (mounted) {
      setState(() => _playerReleased = false);
    }
  }

  Future<void> _untilDismissed(Animation<double>? animation) async {
    if (animation == null || animation.isDismissed) {
      return;
    }
    final dismissed = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.dismissed && !dismissed.isCompleted) {
        dismissed.complete();
      }
    }

    animation.addStatusListener(onStatus);
    try {
      await dismissed.future.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // A route that never finishes sliding must not leave a blank player.
    } finally {
      animation.removeStatusListener(onStatus);
    }
  }

  /// Tapping a clip time sets it to where the video is now (spec FR-5).
  void _setEdgeToPlayhead(void Function(Duration videoTime) setEdge) {
    if (_playhead.isReady) {
      setEdge(_playhead.position);
    }
  }

  /// One keyframe is written when a drag ends; it becomes the selected one.
  void _moveCropTo(
    ReelDraftController controller,
    Duration time,
    CropAnchor anchor,
  ) {
    controller.moveCropTo(time, anchor);
    final keyframes = ref.read(reelDraftProvider).frame.cropPath.keyframes;
    final nearest = keyframes.indexed.reduce(
      (best, next) => (next.$2.time - time).abs() < (best.$2.time - time).abs()
          ? next
          : best,
    );
    setState(() => _selectedKeyframe = nearest.$1);
  }

  void _selectKeyframe(CropPath path, int index) {
    setState(() => _selectedKeyframe = index);
    if (_playhead.isReady) {
      unawaited(_playhead.seekTo(path.keyframes[index].time));
    }
  }

  Widget _scrollingBody(
    ReelDraft draft,
    SourceVideo video,
    ClipRange clip,
    ReelDraftController controller,
    OutputSize sourceSize,
    FollowState follow,
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
                onSetToPlayhead: () =>
                    _setEdgeToPlayhead(controller.setClipStartAt),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NudgeCard(
                edge: _ClipEdge.end,
                time: clip.end,
                onNudge: controller.nudgeClipEnd,
                onSetToPlayhead: () =>
                    _setEdgeToPlayhead(controller.setClipEndAt),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const HintText(
          'Tap a time to set it to where the video is now, or nudge it.',
        ),
        const SizedBox(height: 24),
        FrameControls(
          frame: draft.frame,
          sourceSize: sourceSize,
          onChanged: controller.updateFrame,
        ),
        // Kept while moving, so a crop that can no longer move (Blur, 16:9)
        // can still be turned off.
        if (canMoveCrop(draft.frame, sourceSize) ||
            !draft.frame.cropPath.isEmpty)
          _MovingCropSwitch(
            moving: !draft.frame.cropPath.isEmpty,
            onChanged: (moving) {
              setState(() => _selectedKeyframe = 0);
              if (moving) {
                controller.startMovingCrop();
              } else {
                controller.stopMovingCrop();
              }
            },
          ),
        if (canMoveCrop(draft.frame, sourceSize) &&
            !draft.frame.cropPath.isEmpty)
          FollowSubjectSection(
            state: follow,
            canStart:
                ref.watch(clipSourceProvider(video.videoId)).value != null,
            onStart: _follow,
            onCancel: ref.read(followSubjectProvider.notifier).cancel,
          ),
        if (draft.frame.preset == AspectPreset.free) ...[
          const SizedBox(height: 16),
          FreeCropEditor(
            crop: draft.frame.freeCrop,
            // While the crop moves its keyframes place the window, so a drag
            // may only change its size.
            onChanged: (crop) => controller.updateFrame(
              draft.frame.copyWith(
                freeCrop: draft.frame.cropPath.isEmpty
                    ? crop
                    : draft.frame.freeCrop.copyWith(
                        width: crop.width,
                        height: crop.height,
                      ),
              ),
            ),
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
        color: AppColors.surface,
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
        title: const Text('Move the crop during the clip'),
        subtitle: const HintText(
          'Play the video and drag the crop window to where it should be at '
          'that moment. It glides or cuts to each new place.',
        ),
        value: moving,
        onChanged: onChanged,
      ),
    );
  }
}
