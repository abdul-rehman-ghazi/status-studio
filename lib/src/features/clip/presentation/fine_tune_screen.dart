import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/route_animation.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/presentation/clip_source_player.dart';
import 'package:status_studio/src/features/clip/presentation/crop_window_overlay.dart';
import 'package:status_studio/src/features/clip/presentation/fine_tune_crop_tab.dart';
import 'package:status_studio/src/features/clip/presentation/fine_tune_trim_tab.dart';
import 'package:status_studio/src/features/clip/presentation/person_chooser_sheet.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/features/transcript/presentation/script_opening_notice_host.dart';
import 'package:status_studio/src/routing/app_router.dart';

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
    final isFreeCrop = draft.frame.preset == AspectPreset.free;
    ref.listen(followSubjectProvider, _showHowFollowEnded);
    return Scaffold(
      appBar: FlowAppBar(
        title: 'Fine-tune · Video',
        stepLabel: draft.lyricsSkipped ? 'Step 2 of 3' : 'Step 2 of 4',
      ),
      // The player stays put while the tab under it scrolls, so the crop can
      // be moved with the video in view.
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const ScriptOpeningNoticeHost(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _playerReleased
                  ? const ClipPlayerPlaceholder()
                  : ClipSourcePlayer(
                      video: video,
                      clip: clip,
                      playhead: _playhead,
                      videoOverlay: canMove || isFreeCrop
                          ? CropWindowOverlay(
                              frame: draft.frame,
                              sourceSize: sourceSize,
                              playhead: _playhead,
                              editable: !path.isEmpty || isFreeCrop,
                              onMoved: (time, anchor) =>
                                  _onCropDragged(controller, time, anchor),
                              onResized: controller.resizeFreeCrop,
                            )
                          : null,
                    ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Trim'),
                Tab(text: 'Crop'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  FineTuneTrimTab(
                    video: video,
                    clip: clip,
                    playhead: _playhead,
                  ),
                  FineTuneCropTab(
                    selectedKeyframe: _selectedKeyframe,
                    playhead: _playhead,
                    actions: CropTabActions(
                      onSpanSelected: _selectSpan,
                      onMovingChanged: (moving) =>
                          _setMoving(controller, moving),
                      onAddPosition: () => _addPosition(controller),
                      onFollow: () => unawaited(_follow()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          onPressed: _openNextStep,
          child: Text(draft.lyricsSkipped ? 'Next: caption' : 'Next: lyrics'),
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

  /// Asks what to keep in frame in one scene (spec FR-27). The sheet closes
  /// once with its answer, and only then is the answer acted on; leaving it
  /// any other way is a cancel.
  Future<void> _askWhat(FollowChoosing choosing) async {
    final answer = await showModalBottomSheet<SceneAnswer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => PersonChooserSheet(
        choosing: choosing,
        onAnswered: (answer) => Navigator.of(sheet).pop(answer),
      ),
    );
    if (!mounted) {
      return;
    }
    ref
        .read(followSubjectProvider.notifier)
        .answer(choosing, answer ?? const Cancelled());
  }

  /// Says how a run ended (spec FR-23), then clears it.
  void _showHowFollowEnded(FollowState? before, FollowState after) {
    if (after is FollowChoosing) {
      unawaited(_askWhat(after));
      return;
    }
    final message = switch (after) {
      FollowDone(:final keyframeCount) =>
        'The crop follows your choices ($keyframeCount '
            '${keyframeCount == 1 ? 'keyframe' : 'keyframes'}). '
            'Drag the crop or tap a position to adjust.',
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

  /// Lyrics, or Caption for a reel without lyrics (spec FR-29), starts its
  /// own player only once this step's is gone, and this step makes its
  /// player again only once that step has slid away: never two decoders at a
  /// time (spec FR-22).
  Future<void> _openNextStep() async {
    if (_playerReleased) {
      return;
    }
    ref.read(followSubjectProvider.notifier).cancel();
    setState(() => _playerReleased = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      setState(() => _playerReleased = false);
      return;
    }
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    final nextStep = ref.read(reelDraftProvider).lyricsSkipped
        ? AppRoutes.style
        : AppRoutes.lyrics;
    await context.push(nextStep);
    await untilDismissed(covered);
    if (mounted) {
      setState(() => _playerReleased = false);
    }
  }

  /// A still free crop is moved itself; any other drag writes a keyframe.
  void _onCropDragged(
    ReelDraftController controller,
    Duration time,
    CropAnchor anchor,
  ) {
    final frame = ref.read(reelDraftProvider).frame;
    if (frame.preset == AspectPreset.free && frame.cropPath.isEmpty) {
      _placeFreeCrop(controller, anchor);
      return;
    }
    _moveCropTo(controller, time, anchor);
  }

  /// The anchor is a place in the room around the window (spec FR-22), so
  /// the rectangle's corner is that share of the room.
  void _placeFreeCrop(ReelDraftController controller, CropAnchor anchor) {
    final frame = ref.read(reelDraftProvider).frame;
    final crop = frame.freeCrop;
    controller.updateFrame(
      frame.copyWith(
        freeCrop: crop.copyWith(
          left: anchor.x * (1 - crop.width),
          top: anchor.y * (1 - crop.height),
        ),
      ),
    );
  }

  /// One keyframe is written when a drag ends; it becomes the selected one.
  void _moveCropTo(
    ReelDraftController controller,
    Duration time,
    CropAnchor anchor,
  ) {
    controller.moveCropTo(time, anchor);
    _selectKeyframeNearest(time);
  }

  /// New position here (spec FR-22): a keyframe at the playhead holding the
  /// crop where it is, selected so it can be dragged next.
  void _addPosition(ReelDraftController controller) {
    final clip = ref.read(reelDraftProvider).clip;
    if (clip == null || !_playhead.isReady) {
      return;
    }
    final time = _playhead.position;
    if (time < clip.start || time > clip.end) {
      _showSnackBar('Play or seek inside the clip first.');
      return;
    }
    controller.addCropPosition(time);
    _selectKeyframeNearest(time);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectKeyframeNearest(Duration time) {
    final keyframes = ref.read(reelDraftProvider).frame.cropPath.keyframes;
    final nearest = keyframes.indexed.reduce(
      (best, next) => (next.$2.time - time).abs() < (best.$2.time - time).abs()
          ? next
          : best,
    );
    setState(() => _selectedKeyframe = nearest.$1);
  }

  /// Seeks to where the block's crop shows: a Cut's keyframe sits just
  /// before its cut, and the first block may start after its keyframe.
  void _selectSpan(CropSpan span) {
    setState(() => _selectedKeyframe = span.keyframeIndex);
    if (!_playhead.isReady) {
      return;
    }
    final keyframes = ref.read(reelDraftProvider).frame.cropPath.keyframes;
    final keyframe = keyframes[span.keyframeIndex];
    final at = keyframe.time == span.start ? keyframe.shownAt : span.start;
    unawaited(_playhead.seekTo(at));
  }

  void _setMoving(ReelDraftController controller, bool moving) {
    setState(() => _selectedKeyframe = 0);
    if (moving) {
      controller.startMovingCrop();
    } else {
      controller.stopMovingCrop();
    }
  }
}
