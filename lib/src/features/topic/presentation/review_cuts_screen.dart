import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/features/join/application/background_clip_maker.dart';
import 'package:status_studio/src/features/join/application/clip_maker.dart';
import 'package:status_studio/src/features/join/application/cut_previewer.dart';
import 'package:status_studio/src/features/join/application/whole_video.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/join/presentation/cut_player_sheet.dart';
import 'package:status_studio/src/features/join/presentation/making_view.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/topic/application/link_session_saver.dart';
import 'package:status_studio/src/features/topic/application/moment_words_writer.dart';
import 'package:status_studio/src/features/topic/application/topic_finder.dart';
import 'package:status_studio/src/features/topic/application/topic_progress.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/topic/presentation/moments_panel.dart';
import 'package:status_studio/src/features/topic/presentation/script_page.dart';
import 'package:status_studio/src/features/topic/presentation/transition_picker.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_consent_screen.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_key_settings_route.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_shortfall_question.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// Gets a linked video's script, then the script page where the user picks
/// the moments, with the transition and Make the clip (spec FR-43, FR-37).
/// Kept as it changes, to continue from Recent (FR-38).
class ReviewCutsScreen extends ConsumerStatefulWidget {
  const ReviewCutsScreen({required this.request, this.continued, super.key});

  /// Opens the session left on Review cuts: its cuts replace the found ones.
  ReviewCutsScreen.continuing(LinkSession session, {super.key})
    : request = session.request,
      continued = session;

  final TopicRequest request;
  final LinkSession? continued;

  @override
  ConsumerState<ReviewCutsScreen> createState() => _ReviewCutsScreenState();
}

class _ReviewCutsScreenState extends ConsumerState<ReviewCutsScreen> {
  StreamSubscription<TopicProgress>? _search;
  TopicProgress? _progress;
  Object? _failure;
  List<ReviewCut>? _cuts;
  List<TranscriptBlock> _blocks = const [];
  var _edited = false;
  var _transition = ClipTransition.crossfade;

  /// A continued session's cuts, shown in place of the first found list.
  List<ReviewCut>? _keptCuts;
  late final LinkSessionSaver _saver;
  MakingProgress? _making;
  var _writingWords = false;
  var _momentsOpen = false;
  TopicCut? _preparingPlay;
  Object? _makeFailure;

  /// Asked once while the screen is open (spec FR-50, *Claude's call*).
  var _wholeVideo = WholeVideoAnswer.notAsked;

  @override
  void initState() {
    super.initState();
    // Read now: a save after leaving the screen can't use ref.
    _saver = ref.read(linkSessionSaverProvider);
    if (widget.continued case final session?) {
      _keptCuts = session.cuts;
      _edited = session.edited;
      _transition = session.transition;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_begin()));
  }

  @override
  void dispose() {
    unawaited(_stopSearch());
    if (_making != null) {
      unawaited(ref.read(backgroundClipMakerProvider).cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back closes Your moments before it leaves Review cuts (spec FR-46).
    return PopScope(
      canPop: !_momentsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeMoments();
      },
      child: _scaffold(),
    );
  }

  void _closeMoments() => setState(() => _momentsOpen = false);

  Widget _scaffold() {
    final cuts = _cuts;
    return Scaffold(
      appBar: AppBar(
        title: const ScreenTitle('Review cuts'),
        actions: [
          if (cuts != null && _making == null && _writingWords)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (cuts != null &&
              _making == null &&
              cutsNeedingWords(cuts).isNotEmpty)
            IconButton(
              tooltip: 'Update words',
              icon: const Icon(Icons.translate),
              onPressed: () => unawaited(_updateWords()),
            ),
        ],
      ),
      body: _body(cuts),
      bottomNavigationBar:
          cuts == null ||
              _failure != null ||
              _making != null ||
              _makeFailure != null
          ? null
          : _ReviewFooter(
              summary: (
                momentCount: cuts.length,
                total: totalLength(tickedCuts(cuts)),
                transition: _transition,
              ),
              actions: (
                onMoments: () => setState(() => _momentsOpen = !_momentsOpen),
                onTransition: _setTransition,
                onMake: tickedCuts(cuts).isEmpty
                    ? null
                    : () => unawaited(_make()),
              ),
            ),
    );
  }

  Widget _body(List<ReviewCut>? cuts) {
    if (_makeFailure case final failure?) {
      return MakeFailureView(
        failure: failure,
        onTryAgain: () => unawaited(_make()),
        onBack: () => setState(() => _makeFailure = null),
      );
    }
    if (_making case final making?) {
      return MakingView(
        progress: making,
        onCancel: () =>
            unawaited(ref.read(backgroundClipMakerProvider).cancel()),
      );
    }
    if (_failure case final failure?) {
      return _FailureView(
        failure: failure,
        onTryAgain: _find,
        onBack: () => context.pop(),
      );
    }
    if (cuts == null) {
      return _SearchProgress(
        progress: _progress,
        waitingLabel: 'Getting the script',
        onCancel: () => unawaited(_cancel()),
      );
    }
    return Stack(
      children: [_scriptPage(), if (_momentsOpen) _momentsPanel(cuts)],
    );
  }

  Widget _scriptPage() => ScriptPage(
    content: ScriptPageContent(blocks: _blocks, usedReels: _reelsOfThisVideo()),
    onAddRun: (run) => _edit((cuts) => addBlocksAsCut(cuts, run)),
  );

  Widget _momentsPanel(List<ReviewCut> cuts) => MomentsPanel(
    content: MomentsPanelContent(
      cuts: cuts,
      preparingPlay: _preparingPlay,
      usedReels: _reelsOfThisVideo(),
    ),
    actions: MomentActions(
      onToggle: _toggle,
      onPlay: (cut) => unawaited(_play(cut)),
      onReorder: _reorder,
    ),
    onClose: _closeMoments,
  );

  /// The reels made from this linked video, for the used marks (spec
  /// FR-44).
  List<RecentReel> _reelsOfThisVideo() {
    final videoKey = widget.request.source.key;
    final reels = ref.watch(recentReelsProvider).value ?? const [];
    return [
      for (final reel in reels)
        if (reel.videoKey == videoKey) reel,
    ];
  }

  /// Downloads the moment at up to 480p, then plays it (spec FR-37). One
  /// at a time. A site without parts asks first (FR-50).
  Future<void> _play(TopicCut cut) async {
    if (_preparingPlay != null) {
      return;
    }
    setState(() => _preparingPlay = cut);
    try {
      final order = PreviewOrder(
        video: switch (widget.request.source) {
          LinkedMoments(:final video) => video,
          LocalMoments() => throw UnsupportedError('M71 task 4'),
        },
        cut: cut,
        wholeVideo: _wholeVideo,
      );
      final file = await ref.read(cutPreviewerProvider).prepare(order);
      if (!mounted) {
        return;
      }
      setState(() => _preparingPlay = null);
      await showCutPlayer(
        context,
        CutPlayerStart(
          file: file,
          cut: cut,
          nudge: _nudgerFor(cut),
          download: (moved) =>
              ref.read(cutPreviewerProvider).prepare(order.withCut(moved)),
        ),
      );
    } on WholeFileNeededException catch (needed) {
      if (!mounted) {
        return;
      }
      setState(() => _preparingPlay = null);
      if (await _allowWholeVideo(needed)) {
        await _play(cut);
      }
    } on Object {
      // Any failure only means the moment can't be played; say so.
      if (!mounted) {
        return;
      }
      setState(() => _preparingPlay = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't play this moment.")),
      );
    }
  }

  Future<void> _begin() async {
    if (!await _goOnWithTheScript()) {
      if (mounted) context.pop();
      return;
    }
    _keep();
    if (widget.request.source case LinkedMoments(:final video)) {
      unawaited(_saver.saveVideo(video));
    }
    _find();
  }

  /// Nothing is asked when nothing goes to Groq: captions or a saved
  /// script. A continued session skips the long-script question, answered
  /// when it began (spec FR-36), but not Groq's allowance, which may have
  /// run low since (FR-45). The whole video counts: the link's partial run
  /// is found only after the audio downloads.
  Future<bool> _goOnWithTheScript() async {
    final request = widget.request;
    if (captionsUrlFor(request) != null || await _isScriptSaved()) {
      return true;
    }
    if (widget.continued == null &&
        needsLongScriptWarning(request) &&
        !await _confirmLongScript()) {
      return false;
    }
    if (!mounted) {
      return false;
    }
    return goOnWhenGroqIsShort(context, ref, request.source.duration);
  }

  /// An unreadable store counts as no script: asking is the safe side.
  Future<bool> _isScriptSaved() async {
    final request = widget.request;
    try {
      final store = await ref.read(topicStoreProvider.future);
      final saved = await store.savedBlocks(
        request.source.key,
        request.outputLanguage,
      );
      return saved != null;
    } on Exception {
      return false;
    }
  }

  /// Saves the screen as it is for Recent (spec FR-38).
  void _keep() => unawaited(
    _saver.save(
      LinkSession(
        request: widget.request,
        cuts: _cuts ?? _keptCuts,
        transition: _transition,
        edited: _edited,
        savedAt: DateTime.now(),
      ),
    ),
  );

  void _setTransition(ClipTransition chosen) {
    setState(() => _transition = chosen);
    _keep();
  }

  void _find() {
    unawaited(_search?.cancel());
    setState(() {
      _progress = null;
      _failure = null;
      _cuts = null;
    });
    _search = ref
        .read(topicFinderProvider)
        .find(widget.request)
        .listen(
          _onProgress,
          onError: (Object failure, StackTrace stack) {
            debugPrint('Review cuts failed: $failure\n$stack');
            unawaited(_onFailure(failure));
          },
          cancelOnError: true,
        );
  }

  void _onProgress(TopicProgress progress) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (progress is TopicFound) {
        _showFound(progress);
      }
      _progress = progress;
    });
    if (progress is TopicFound) {
      _keep();
    }
  }

  /// A continued session's moments come back with the script; a new one
  /// starts with none (spec FR-43).
  void _showFound(TopicFound found) {
    final kept = _keptCuts;
    _cuts = kept ?? const [];
    _edited = kept != null && _edited;
    _keptCuts = null;
    _blocks = found.blocks;
    _search = null;
  }

  Future<void> _onFailure(Object failure) async {
    _search = null;
    if (failure is NoGroqConsentException && mounted) {
      if (await askForGroqConsent(context)) {
        _find();
        return;
      }
    }
    if (mounted) setState(() => _failure = failure);
  }

  Future<void> _stopSearch() async {
    final search = _search;
    if (search == null) {
      return;
    }
    _search = null;
    await search.cancel();
    await ref.read(topicFinderProvider).cancel(widget.request);
  }

  Future<void> _cancel() async {
    await _stopSearch();
    if (mounted) context.pop();
  }

  /// Rewrites the words of trimmed and added moments (spec FR-40).
  Future<void> _updateWords() async {
    if (_writingWords) {
      return;
    }
    setState(() => _writingWords = true);
    try {
      await _writeWordsAskingConsent();
    } on Object catch (failure) {
      // Any failure leaves the words waiting; say why.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessageFor(failure))));
      }
    } finally {
      if (mounted) setState(() => _writingWords = false);
    }
  }

  Future<void> _writeWordsAskingConsent() async {
    try {
      await _writeWords();
    } on NoGroqConsentException {
      if (!mounted || !await askForGroqConsent(context)) {
        return;
      }
      await _writeWords();
    }
  }

  Future<void> _writeWords() async {
    final waiting = cutsNeedingWords(_cuts ?? const []);
    if (waiting.isEmpty) {
      return;
    }
    final written = await ref
        .read(momentWordsWriterProvider)
        .write(
          MomentWordsOrder(
            cuts: waiting,
            blocks: _blocks,
            output: widget.request.outputLanguage,
          ),
        );
    if (mounted) _edit((cuts) => withWrittenWords(cuts, written));
  }

  void _edit(List<ReviewCut> Function(List<ReviewCut> cuts) change) {
    final cuts = _cuts;
    if (cuts == null) {
      return;
    }
    setState(() {
      _cuts = change(cuts);
      _edited = true;
    });
    _keep();
  }

  void _nudge(
    int index, {
    Duration startBy = Duration.zero,
    Duration endBy = Duration.zero,
  }) => _edit(
    (cuts) => nudgeCut(
      cuts,
      CutNudge(index: index, startBy: startBy, endBy: endBy),
      videoLength: widget.request.source.duration,
    ),
  );

  /// The Play sheet's nudges (spec FR-39), applied to the card as the
  /// card's own are. The moment is found by its times, which change with
  /// each nudge; the list can't be reordered while the sheet is open.
  TopicCut Function({Duration startBy, Duration endBy}) _nudgerFor(
    TopicCut cut,
  ) {
    var current = cut;
    return ({startBy = Duration.zero, endBy = Duration.zero}) {
      final index = (_cuts ?? const []).indexWhere(
        (review) => review.cut == current,
      );
      if (index < 0) {
        return current;
      }
      _nudge(index, startBy: startBy, endBy: endBy);
      current = _cuts![index].cut;
      return current;
    };
  }

  void _toggle(int index) => _edit((cuts) => toggleCut(cuts, index));

  void _reorder(int from, int to) => _edit((cuts) {
    final reordered = [...cuts];
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    return reordered;
  });

  /// Downloads and joins the ticked cuts, then opens Fine-tune · Video on
  /// the joined clip (spec FR-37). Cancel returns to the list.
  Future<void> _make() async {
    final ticked = tickedCuts(_cuts ?? const []);
    if (ticked.isEmpty) {
      return;
    }
    setState(() {
      _makeFailure = null;
      _momentsOpen = false;
      _making = const ReadingStreams();
    });
    try {
      final made = await ref.read(backgroundClipMakerProvider).make(
        ClipOrder(
          request: widget.request,
          cuts: ticked,
          transition: _transition,
          wholeVideo: _wholeVideo,
        ),
        (progress) {
          if (mounted) setState(() => _making = progress);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _making = null);
      // The joined clip's own Recent row takes the session's place.
      unawaited(_saver.delete(widget.request.source.key));
      ref.invalidate(isVideoKeptProvider);
      ref.read(reelDraftProvider.notifier).setVideoOn(made.video, made.clip);
      await context.push(AppRoutes.fineTune);
    } on DownloadCancelledException {
      if (mounted) setState(() => _making = null);
    } on WholeFileNeededException catch (needed) {
      if (!mounted) {
        return;
      }
      setState(() => _making = null);
      if (await _allowWholeVideo(needed)) {
        await _make();
      }
    } on Object catch (failure) {
      // Every failure shows on the screen; none may reach the zone.
      if (mounted) {
        setState(() {
          _making = null;
          _makeFailure = failure;
        });
      }
    }
  }

  /// Download keeps the answer while the screen is open; Cancel returns
  /// to the moments (spec FR-50).
  Future<bool> _allowWholeVideo(WholeFileNeededException needed) async {
    final allowed = await _confirm(
      title: 'Whole video',
      message:
          'This site only offers the whole video '
          '(${wholeVideoSizeLabel(needed.totalBytes)}). Download it?',
      confirmLabel: 'Download',
      backLabel: 'Cancel',
    );
    if (allowed && mounted) {
      setState(() => _wholeVideo = WholeVideoAnswer.allowed);
    }
    return allowed && mounted;
  }

  Future<bool> _confirmLongScript() => _confirm(
    title: 'No captions',
    message:
        'This video has no captions in '
        '${widget.request.outputLanguage.label}, so Groq writes its script '
        'first. That takes a while and uses much of Groq\'s free daily '
        'audio.',
    confirmLabel: 'Continue',
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    String backLabel = 'Back',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(backLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

class _SearchProgress extends StatelessWidget {
  const _SearchProgress({
    required this.progress,
    required this.waitingLabel,
    required this.onCancel,
  });

  final TopicProgress? progress;

  /// Shown before the first step comes.
  final String waitingLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_label(context, progress), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress is TopicStep ? progress.fraction : null,
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }

  String _label(BuildContext context, TopicProgress? progress) =>
      switch (progress) {
        TopicStep(:final label) => label,
        TopicFound() || null => waitingLabel,
      };
}

class _FailureView extends ConsumerWidget {
  const _FailureView({
    required this.failure,
    required this.onTryAgain,
    required this.onBack,
  });

  final Object failure;
  final VoidCallback onTryAgain;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            errorMessageFor(failure),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (!hasOwnMessage(failure)) ...[
            const SizedBox(height: 8),
            SelectableText(
              '$failure',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          if (failure is NoGroqKeyException)
            FilledButton(
              onPressed: () => unawaited(_openKeySettings(context, ref)),
              child: const Text('Settings'),
            )
          else
            FilledButton(onPressed: onTryAgain, child: const Text('Try again')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }

  /// Back from Settings with a key saved, the failed step runs again; without
  /// one the failure stays (spec §8, M67).
  Future<void> _openKeySettings(BuildContext context, WidgetRef ref) async {
    if (await keySavedAfterGroqSettings(context, ref)) {
      onTryAgain();
    }
  }
}

/// What the footer sums up.
typedef _FooterSummary = ({
  int momentCount,

  /// The ticked moments added up: "58 s" (spec FR-43; there is no length
  /// to measure it against since M53).
  Duration total,
  ClipTransition transition,
});

/// What the footer's buttons do; [onMake] is null until a moment is ticked.
typedef _FooterActions = ({
  VoidCallback onMoments,
  ValueChanged<ClipTransition> onTransition,
  VoidCallback? onMake,
});

/// Moments (n), which opens Your moments over the script (spec FR-46), the
/// total, the transition (its four previews open in a sheet) and Make the
/// clip, kept short so the script has the screen.
class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({required this.summary, required this.actions});

  final _FooterSummary summary;
  final _FooterActions actions;

  Future<void> _chooseTransition(BuildContext context) async {
    final chosen = await showTransitionSheet(context, summary.transition);
    if (chosen != null) actions.onTransition(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: actions.onMoments,
                  icon: const Icon(Icons.format_list_bulleted),
                  label: Text('Moments (${summary.momentCount})'),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('${summary.total.inSeconds} s')),
                TextButton.icon(
                  onPressed: () => unawaited(_chooseTransition(context)),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(summary.transition.label),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: actions.onMake,
              child: const Text('Make the clip'),
            ),
          ],
        ),
      ),
    );
  }
}
