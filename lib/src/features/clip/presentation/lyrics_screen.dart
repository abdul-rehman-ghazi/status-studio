import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/route_animation.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/presentation/clip_lines_list.dart';
import 'package:status_studio/src/features/clip/presentation/clip_source_player.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/features/style/presentation/reel_stage.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/presentation/script_tools.dart';
import 'package:status_studio/src/features/transcript/presentation/script_writing_footer.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// Step 2 of Fine-tune: the clip's lines, when each one shows, and the video
/// with them on it (spec FR-21).
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  static const _saveDelay = Duration(seconds: 1);

  final _playhead = ClipPlayhead();

  /// True while Caption and Export are open: this player's decoder would
  /// leave the export's too little memory (one decoder at a time, spec
  /// FR-22).
  var _playerReleased = false;
  late final ScriptEditingService _scriptEditing;
  late final AppLifecycleListener _lifecycle;
  Timer? _saveTimer;
  Future<void> Function()? _pendingSave;

  @override
  void initState() {
    super.initState();
    // Read now: dispose saves a pending edit and can't use ref.
    _scriptEditing = ref.read(scriptEditingServiceProvider);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_savePending()));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _lifecycle.dispose();
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

  /// The script is about to be written again, so a line edit still waiting
  /// to be saved must not land on top of the new one.
  void _dropPendingSave() {
    _saveTimer?.cancel();
    _pendingSave = null;
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

  /// Caption opens only once this step's player is gone, and the player comes
  /// back only once Caption has slid away.
  Future<void> _openStyle() async {
    // A second tap before the push must not open Caption twice.
    if (_playerReleased) {
      return;
    }
    setState(() => _playerReleased = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      // Back was pressed meanwhile; pushing now would open Caption over the
      // wrong screen.
      setState(() => _playerReleased = false);
      return;
    }
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    await context.push(AppRoutes.style);
    await untilDismissed(covered);
    if (mounted) {
      setState(() => _playerReleased = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final clip = draft.clip;
    final video = draft.video;
    if (clip == null || video == null) {
      throw StateError('Lyrics opened without a video and a clip.');
    }
    return Scaffold(
      appBar: const FlowAppBar(
        title: 'Fine-tune · Lyrics',
        stepLabel: 'Step 3 of 4',
      ),
      // The player stays put while the lines scroll, so they can be tapped
      // with the video in view.
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
                    onlyRange: clip,
                    frame: (context, videoWidget) => ReelStage(
                      draft: draft,
                      sourceSize: previewSourceSize(ref, draft),
                      video: videoWidget,
                      playhead: _playhead,
                    ),
                  ),
          ),
          Expanded(child: _lines(draft)),
        ],
      ),
      bottomNavigationBar: ScriptWritingFooter(
        child: BottomAction(
          child: FilledButton(
            onPressed: () => unawaited(_openStyle()),
            child: const Text('Next: caption'),
          ),
        ),
      ),
    );
  }

  Widget _lines(ReelDraft draft) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ScriptTools(onRewriting: _dropPendingSave),
        const SizedBox(height: 8),
        const HintText(
          'Tap a line to jump to it. While the clip plays, tap a line when '
          'it starts to set when it shows.',
        ),
        const SizedBox(height: 8),
        ClipLinesList(
          script: draft.pickedScript,
          clip: draft.clip!,
          playhead: _playhead,
          onEdited: _scheduleSave,
        ),
      ],
    );
  }
}
