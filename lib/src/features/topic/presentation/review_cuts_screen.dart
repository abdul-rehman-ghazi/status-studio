import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/features/join/application/background_clip_maker.dart';
import 'package:status_studio/src/features/join/application/clip_maker.dart';
import 'package:status_studio/src/features/join/application/cut_previewer.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/join/presentation/cut_player_sheet.dart';
import 'package:status_studio/src/features/join/presentation/making_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/topic/application/link_session_saver.dart';
import 'package:status_studio/src/features/topic/application/topic_finder.dart';
import 'package:status_studio/src/features/topic/application/topic_progress.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/topic/presentation/add_moment_sheet.dart';
import 'package:status_studio/src/features/topic/presentation/cut_card.dart';
import 'package:status_studio/src/features/topic/presentation/transition_picker.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_consent_screen.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// Finds the moments of a linked video about a topic, then shows them to
/// check, with the transition and Make the clip (spec FR-36, FR-37). Kept
/// as it changes, to continue from Recent (FR-38).
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
  TopicCut? _preparingPlay;
  Object? _makeFailure;

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
    final cuts = _cuts;
    return Scaffold(
      appBar: AppBar(
        title: const ScreenTitle('Review cuts'),
        actions: [
          if (cuts != null && _making == null)
            IconButton(
              tooltip: 'Find again',
              icon: const Icon(Icons.refresh),
              onPressed: () => unawaited(_findAgain()),
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
              total: totalLength(tickedCuts(cuts)),
              length: widget.request.length,
              transition: _transition,
              onTransition: _setTransition,
              onMake: tickedCuts(cuts).isEmpty
                  ? null
                  : () => unawaited(_make()),
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
        onFindAgain: _find,
        onBack: () => context.pop(),
      );
    }
    if (cuts == null) {
      return _SearchProgress(
        progress: _progress,
        onCancel: () => unawaited(_cancel()),
      );
    }
    return _CutList(
      cuts: cuts,
      onToggle: _toggle,
      onReorder: _reorder,
      onAddMoment: () => unawaited(_addMoment()),
      onPlay: (cut) => unawaited(_play(cut)),
      preparingPlay: _preparingPlay,
    );
  }

  /// Downloads the moment at up to 480p, then plays it (spec FR-37). One
  /// at a time.
  Future<void> _play(TopicCut cut) async {
    if (_preparingPlay != null) {
      return;
    }
    setState(() => _preparingPlay = cut);
    try {
      final file = await ref
          .read(cutPreviewerProvider)
          .prepare(widget.request.video, cut);
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
          download: (moved) => ref
              .read(cutPreviewerProvider)
              .prepare(widget.request.video, moved),
        ),
      );
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

  /// A continued session skips the long-script question: it was answered
  /// when the session began.
  Future<void> _begin() async {
    if (widget.continued == null &&
        needsLongScriptWarning(widget.request.video) &&
        !await _confirmLongScript()) {
      if (mounted) context.pop();
      return;
    }
    _keep();
    _find();
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
        .listen(_onProgress, onError: _onFailure, cancelOnError: true);
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

  /// A continued session's cuts win over the found ones once; Find again
  /// later shows what is found.
  void _showFound(TopicFound found) {
    final kept = _keptCuts;
    _cuts = kept ?? untickedCuts(found.cuts);
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

  Future<void> _findAgain() async {
    if (_edited && !await _confirmReplaceEdits()) {
      return;
    }
    _find();
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
      videoLength: widget.request.video.duration,
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

  Future<void> _addMoment() async {
    final block = await showAddMomentSheet(context, _blocks);
    if (block != null) _edit((cuts) => addBlockAsCut(cuts, block));
  }

  /// Downloads and joins the ticked cuts, then opens Fine-tune · Video on
  /// the joined clip (spec FR-37). Cancel returns to the list.
  Future<void> _make() async {
    final ticked = tickedCuts(_cuts ?? const []);
    if (ticked.isEmpty) {
      return;
    }
    setState(() {
      _makeFailure = null;
      _making = const ReadingStreams();
    });
    try {
      final video = await ref.read(backgroundClipMakerProvider).make(
        ClipOrder(
          request: widget.request,
          cuts: ticked,
          transition: _transition,
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
      unawaited(_saver.delete(widget.request));
      ref.invalidate(isVideoKeptProvider);
      ref.read(reelDraftProvider.notifier).setVideo(video);
      await context.push(AppRoutes.fineTune);
    } on DownloadCancelledException {
      if (mounted) setState(() => _making = null);
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

  Future<bool> _confirmLongScript() => _confirm(
    title: 'No captions',
    message:
        'This video has no captions, so Groq writes its script first. That '
        'takes a while and uses much of Groq\'s free daily audio.',
    confirmLabel: 'Continue',
  );

  Future<bool> _confirmReplaceEdits() => _confirm(
    title: 'Replace your edited cuts?',
    message: 'Finding again replaces the cuts you changed.',
    confirmLabel: 'Replace',
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back'),
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
  const _SearchProgress({required this.progress, required this.onCancel});

  final TopicProgress? progress;
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
        WaitingForGroq(:final resumesAt) =>
          "Groq's free limit reached, continuing at "
              '${TimeOfDay.fromDateTime(resumesAt).format(context)}',
        TopicFound() || null => 'Finding the moments',
      };
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.failure,
    required this.onFindAgain,
    required this.onBack,
  });

  final Object failure;
  final VoidCallback onFindAgain;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 20),
          if (failure is NoGroqKeyException)
            FilledButton(
              onPressed: () => context.push(AppRoutes.groqSettings),
              child: const Text('Settings'),
            )
          else
            FilledButton(
              onPressed: onFindAgain,
              child: const Text('Find again'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}

class _CutList extends StatelessWidget {
  const _CutList({
    required this.cuts,
    required this.onToggle,
    required this.onReorder,
    required this.onAddMoment,
    required this.onPlay,
    required this.preparingPlay,
  });

  final List<ReviewCut> cuts;
  final void Function(int index) onToggle;
  final void Function(int from, int to) onReorder;
  final VoidCallback onAddMoment;
  final void Function(TopicCut cut) onPlay;
  final TopicCut? preparingPlay;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: cuts.length,
      onReorderItem: onReorder,
      footer: OutlinedButton.icon(
        onPressed: onAddMoment,
        icon: const Icon(Icons.add),
        label: const Text('Add a moment'),
      ),
      itemBuilder: (context, index) {
        final review = cuts[index];
        return CutCard(
          key: ValueKey(review.cut.start),
          cut: review.cut,
          ticked: review.ticked,
          onToggle: () => onToggle(index),
          onPlay: () => onPlay(review.cut),
          preparingPlay: review.cut == preparingPlay,
        );
      },
    );
  }
}

/// "74 s of 60 s · 14 s over" in the error colour when over: going over is
/// allowed, the length is a target (spec FR-36).
class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.total, required this.length});

  final Duration total;
  final Duration length;

  @override
  Widget build(BuildContext context) {
    final over = total - length;
    final overText = over > Duration.zero ? ' · ${over.inSeconds} s over' : '';
    return Text(
      '${total.inSeconds} s of ${length.inSeconds} s$overText',
      style: over > Duration.zero
          ? TextStyle(color: Theme.of(context).colorScheme.error)
          : null,
    );
  }
}

/// The total, the transition (its four previews open in a sheet) and Make
/// the clip, kept short so the moments have the screen.
class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.total,
    required this.length,
    required this.transition,
    required this.onTransition,
    required this.onMake,
  });

  final Duration total;
  final Duration length;
  final ClipTransition transition;
  final ValueChanged<ClipTransition> onTransition;

  /// Null until a moment is ticked.
  final VoidCallback? onMake;

  Future<void> _chooseTransition(BuildContext context) async {
    final chosen = await showTransitionSheet(context, transition);
    if (chosen != null) onTransition(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _TotalLine(total: total, length: length),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_chooseTransition(context)),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(transition.label),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FilledButton(onPressed: onMake, child: const Text('Make the clip')),
          ],
        ),
      ),
    );
  }
}
