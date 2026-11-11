import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/route_animation.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/application/lyrics_undo_controller.dart';
import 'package:status_studio/src/features/clip/presentation/clip_lines_list.dart';
import 'package:status_studio/src/features/clip/presentation/clip_source_player.dart';
import 'package:status_studio/src/features/clip/presentation/lyrics_get_card.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/features/style/presentation/reel_stage.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/presentation/lyrics_tools.dart';
import 'package:status_studio/src/features/transcript/presentation/script_run_section.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// Step 2 of Fine-tune: everything about the lyrics on one screen (spec
/// FR-21, M30): whether the reel has any, getting them from Groq or typing
/// them, editing and timing them, and how they look. The video plays with
/// them on it.
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> with RouteAware {
  static const _saveDelay = Duration(seconds: 1);

  final _playhead = ClipPlayhead();

  /// True while Export is open: this player's decoder would leave the
  /// export's too little memory (one decoder at a time, spec FR-22).
  var _playerReleased = false;
  late final ScriptEditingService _scriptEditing;
  late final AppLifecycleListener _lifecycle;
  late final RouteObserver<ModalRoute<void>> _routes = ref.read(
    routeObserverProvider,
  );
  Timer? _saveTimer;
  Future<void> Function()? _pendingSave;

  @override
  void initState() {
    super.initState();
    // Read now: dispose saves a pending edit and can't use ref.
    _scriptEditing = ref.read(scriptEditingServiceProvider);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_savePending()));
    unawaited(_openNewestSavedScript());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context) case final route?) {
      _routes.subscribe(this, route);
    }
  }

  /// Whatever Export became (it replaces itself with Done) has been popped,
  /// so the player may come back once that route has slid away. Not on the
  /// push future: Export ending with Done never completes it.
  @override
  void didPopNext() {
    if (_playerReleased) {
      unawaited(_restorePlayer());
    }
  }

  @override
  void dispose() {
    _routes.unsubscribe(this);
    _saveTimer?.cancel();
    _lifecycle.dispose();
    unawaited(_savePending());
    _playhead.dispose();
    super.dispose();
  }

  /// A reel with no lines yet opens on the video's newest saved script, in
  /// any language (spec FR-14, M30). The pipeline reads a saved script
  /// before anything else, so nothing is uploaded.
  Future<void> _openNewestSavedScript() async {
    final draft = ref.read(reelDraftProvider);
    final video = draft.video;
    final run = ref.read(scriptProgressProvider);
    final isIdle = run is AsyncData && run.value == null;
    if (video == null || draft.transcript != null || !isIdle) {
      return;
    }
    final scripts = await ref.read(savedScriptsProvider.future);
    final ofVideo = scripts.where(
      (script) => script.video.videoId == video.videoId,
    );
    if (ofVideo.isEmpty || !mounted) {
      return;
    }
    final newest = ofVideo.reduce(
      (a, b) => a.saved.savedAt.isAfter(b.saved.savedAt) ? a : b,
    );
    ref.read(reelDraftProvider.notifier).setLanguage(newest.language);
    ref.read(scriptProgressProvider.notifier).start(video, newest.language);
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

  /// Export opens only once this step's player is gone, and the player comes
  /// back only once Export has slid away: never two decoders at a time
  /// (spec FR-22).
  Future<void> _openExport() async {
    // A second tap before the push must not open Export twice: two renders
    // would bring the decoder shortage back.
    if (_playerReleased) {
      return;
    }
    unawaited(_savePending());
    setState(() => _playerReleased = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      // Back was pressed meanwhile; pushing now would open Export over the
      // wrong screen.
      setState(() => _playerReleased = false);
      return;
    }
    unawaited(context.push(AppRoutes.export));
  }

  Future<void> _restorePlayer() async {
    await untilDismissed(ModalRoute.of(context)?.secondaryAnimation);
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
    final isWriting = isScriptBeingWritten(ref.watch(scriptProgressProvider));
    return Scaffold(
      appBar: FlowAppBar(
        title: 'Fine-tune · Lyrics',
        stepLabel: 'Step 2 of 2',
        actions: [_UndoRedoButtons(onChanged: _scheduleSave)],
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
          Expanded(child: _lyrics(draft, isWriting)),
        ],
      ),
      bottomNavigationBar: _ExportBar(
        isWriting: isWriting,
        onExport: () => unawaited(_openExport()),
      ),
    );
  }

  Widget _lyrics(ReelDraft draft, bool isWriting) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _LyricsSwitch(
          shown: draft.lyricsShown,
          onChanged: (shown) => _setLyricsShown(shown, isWriting),
        ),
        const SizedBox(height: 8),
        if (draft.lyricsShown)
          ..._shownLyrics(draft, isWriting)
        else
          const HintText(
            'No lyrics on this reel. Nothing leaves your phone and you need '
            'no key.',
          ),
      ],
    );
  }

  List<Widget> _shownLyrics(ReelDraft draft, bool isWriting) {
    if (draft.selection is! RangeSelected) {
      return _beforeLines(draft, isWriting);
    }
    return [
      LyricsTools(onGetAgain: () => unawaited(_getAgain())),
      const ScriptRunSection(),
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
    ];
  }

  /// No lines inside the clip yet: the run under way, or the Get card.
  List<Widget> _beforeLines(ReelDraft draft, bool isWriting) {
    final run = ref.watch(scriptProgressProvider);
    final hasScriptOutsideClip =
        draft.transcript?.lines.isNotEmpty == true && !isWriting;
    return [
      const ScriptRunSection(),
      if (!isWriting && !run.hasError) ...[
        if (hasScriptOutsideClip)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: HintText('The script has no lines inside this clip.'),
          ),
        LyricsGetCard(
          initialLanguage: draft.language,
          onGet: _getLyrics,
          onType: () => unawaited(_typeLyrics()),
        ),
      ],
    ];
  }

  /// Off stops a script still being written (spec FR-29); the lines stay.
  void _setLyricsShown(bool shown, bool isWriting) {
    final controller = ref.read(reelDraftProvider.notifier);
    if (shown) {
      controller.showLyrics();
      return;
    }
    if (isWriting) {
      ref.read(scriptProgressProvider.notifier).cancel();
    }
    controller.hideLyrics();
  }

  void _getLyrics(ScriptLanguage language) {
    final video = ref.read(reelDraftProvider).video;
    if (video == null) {
      return;
    }
    _dropPendingSave();
    ref.read(reelDraftProvider.notifier)
      ..forgetLineEdits()
      ..setLanguage(language);
    ref.read(lyricsUndoProvider.notifier).clear();
    ref.read(scriptProgressProvider.notifier).start(video, language);
  }

  Future<void> _typeLyrics() async {
    final text = await askLineText(context, title: 'First line');
    if (text == null || text.trim().isEmpty || !mounted) {
      return;
    }
    final clip = ref.read(reelDraftProvider).clip!;
    final at = _playhead.isReady ? _playhead.position : clip.start;
    ref.read(reelDraftProvider.notifier).startTypedLyrics(text.trim(), at);
    _scheduleSave();
  }

  /// The same language writes the script again with Groq; another opens
  /// its saved script, or writes one (spec FR-14, M30).
  Future<void> _getAgain() async {
    final draft = ref.read(reelDraftProvider);
    final video = draft.video;
    if (video == null) {
      return;
    }
    if (draft.linesEdited && !await _confirmReplacingEdits()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final language = await _askLanguage(draft.language);
    if (language == null || !mounted) {
      return;
    }
    _dropPendingSave();
    ref.read(reelDraftProvider.notifier)
      ..forgetLineEdits()
      ..setLanguage(language);
    ref.read(lyricsUndoProvider.notifier).clear();
    final run = ref.read(scriptProgressProvider.notifier);
    if (language == draft.language) {
      run.writeAgain(video, language);
    } else {
      run.start(video, language);
    }
  }

  Future<bool> _confirmReplacingEdits() async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace your edited lines?'),
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

  Future<ScriptLanguage?> _askLanguage(ScriptLanguage current) {
    return showDialog<ScriptLanguage>(
      context: context,
      builder: (context) => _GetAgainDialog(current: current),
    );
  }
}

class _LyricsSwitch extends StatelessWidget {
  const _LyricsSwitch({required this.shown, required this.onChanged});

  final bool shown;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Show lyrics on the clip'),
      value: shown,
      onChanged: onChanged,
    );
  }
}

/// Export waits for a script still being written, so a reel never goes out
/// with half its lines (M30).
class _ExportBar extends StatelessWidget {
  const _ExportBar({required this.isWriting, required this.onExport});

  final bool isWriting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isWriting)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: HintText('Wait for the lyrics, or Cancel.'),
          ),
        BottomAction(
          child: FilledButton(
            onPressed: isWriting ? null : onExport,
            child: const Text('Export reel'),
          ),
        ),
      ],
    );
  }
}

class _GetAgainDialog extends StatefulWidget {
  const _GetAgainDialog({required this.current});

  final ScriptLanguage current;

  @override
  State<_GetAgainDialog> createState() => _GetAgainDialogState();
}

class _GetAgainDialogState extends State<_GetAgainDialog> {
  late ScriptLanguage _language = widget.current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Get the lyrics again'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScriptLanguagePicker(
            language: _language,
            onChanged: (language) => setState(() => _language = language),
          ),
          const SizedBox(height: 10),
          HintText(
            _language == widget.current
                ? 'Groq writes them again with your key.'
                : 'Opens the saved script in this language, or Groq writes '
                      'one.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_language),
          child: const Text('Get'),
        ),
      ],
    );
  }
}

/// Undo and Redo for the lines (spec FR-34). Watching the history keeps it
/// while Lyrics is open; it goes with the screen.
class _UndoRedoButtons extends ConsumerWidget {
  const _UndoRedoButtons({required this.onChanged});

  /// Saves the lines after a step, like any edit.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(lyricsUndoProvider);
    final controller = ref.read(lyricsUndoProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Undo',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.undo),
          onPressed: history.canUndo
              ? () => _step(context, controller.undo)
              : null,
        ),
        IconButton(
          tooltip: 'Redo',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.redo),
          onPressed: history.canRedo
              ? () => _step(context, controller.redo)
              : null,
        ),
      ],
    );
  }

  void _step(BuildContext context, VoidCallback step) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    step();
    onChanged();
  }
}
