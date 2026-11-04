import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/lyrics/application/lyrics_service.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class ScriptScreen extends ConsumerWidget {
  const ScriptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reelDraftProvider);
    final transcript = draft.transcript;
    if (transcript == null) {
      throw StateError('The Script screen opened without a transcript.');
    }
    final controller = ref.read(reelDraftProvider.notifier);
    final rangePicked = draft.selection is RangeSelected;
    return Scaffold(
      appBar: const FlowAppBar(
        title: 'Pick the lines',
        stepLabel: 'Step 2 of 4',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _LanguagePicker(
              draft: draft,
              onChanged: (language) => _rewriteScript(context, ref, language),
            ),
          ),
          if (ref.watch(scriptProgressProvider).value?.savedAt
              case final savedAt?)
            _SavedScriptBanner(
              savedAt: savedAt,
              onWriteAgain: () => _writeAgain(context, ref),
            ),
          _ScriptTools(
            draft: draft,
            scriptIsBeingWritten: _isBeingWritten(
              ref.watch(scriptProgressProvider),
            ),
          ),
          _PickHint(text: _pickHint(draft)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: transcript.lines.length,
              itemBuilder: (context, index) => _ScriptLineTile(
                line: transcript.lines[index],
                selection: draft.selection,
                onTap: () => controller.tapLine(index),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ScriptFooter(
        run: ref.watch(scriptProgressProvider),
        onRetry: () => _resume(ref),
        child: BottomAction(
          child: FilledButton(
            onPressed: rangePicked
                ? () => context.push(AppRoutes.fineTune)
                : null,
            child: Text(
              rangePicked ? 'Next: fine-tune' : 'Pick a start and an end',
            ),
          ),
        ),
      ),
    );
  }

  /// Starts the run again; Whisper resumes from its saved progress.
  void _resume(WidgetRef ref) {
    final draft = ref.read(reelDraftProvider);
    if (draft.video case final video?) {
      ref.read(scriptProgressProvider.notifier).start(video, draft.language);
    }
  }

  void _writeAgain(BuildContext context, WidgetRef ref) {
    final draft = ref.read(reelDraftProvider);
    if (draft.video case final video?) {
      ref
          .read(scriptProgressProvider.notifier)
          .writeAgain(video, draft.language);
      context.pushReplacement(AppRoutes.processing);
    }
  }

  void _rewriteScript(
    BuildContext context,
    WidgetRef ref,
    ScriptLanguage language,
  ) {
    ref.read(reelDraftProvider.notifier).setLanguage(language);
    if (ref.read(reelDraftProvider).video case final video?) {
      ref.read(scriptProgressProvider.notifier).start(video, language);
    }
    context.pushReplacement(AppRoutes.processing);
  }
}

bool _isBeingWritten(AsyncValue<ScriptProgress> run) {
  final progress = run.value;
  return progress != null && progress.stage != ScriptStage.done;
}

String _pickHint(ReelDraft draft) {
  return switch ((draft.selection, draft.clip)) {
    (RangeSelected(), final ClipRange clip) =>
      'Clip ${formatTimestamp(clip.start)} – ${formatTimestamp(clip.end)} · '
          '${formatSeconds(clip.length)}. Tap a line to start over.',
    (StartSelected(), _) => 'Now tap the line where it ends',
    _ => 'Tap the line where your clip starts',
  };
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.draft, required this.onChanged});

  final ReelDraft draft;
  final ValueChanged<ScriptLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ScriptLanguage>(
      initialValue: draft.language,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Language'),
      items: [
        for (final language in ScriptLanguage.values)
          DropdownMenuItem(value: language, child: Text(_labelFor(language))),
      ],
      onChanged: (language) {
        if (language == null || language == draft.language) {
          return;
        }
        onChanged(language);
      },
    );
  }

  String _labelFor(ScriptLanguage language) =>
      scriptLanguageLabel(language, draft.transcript?.languageCode);
}

/// Compact, so the three tools fit one row and the lines keep their room.
final _toolButtonStyle = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// The script's fixing tools on one row, so the lines keep their room.
class _ScriptTools extends StatelessWidget {
  const _ScriptTools({required this.draft, required this.scriptIsBeingWritten});

  final ReelDraft draft;
  final bool scriptIsBeingWritten;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        children: [
          _LyricsAction(
            draft: draft,
            scriptIsBeingWritten: scriptIsBeingWritten,
          ),
          _AiFixActions(
            draft: draft,
            scriptIsBeingWritten: scriptIsBeingWritten,
          ),
        ],
      ),
    );
  }
}

/// FR-17: swaps the script for the song's published lyrics.
class _LyricsAction extends ConsumerStatefulWidget {
  const _LyricsAction({
    required this.draft,
    required this.scriptIsBeingWritten,
  });

  final ReelDraft draft;

  /// Lines still arriving would overwrite the lyrics, so wait for them.
  final bool scriptIsBeingWritten;

  @override
  ConsumerState<_LyricsAction> createState() => _LyricsActionState();
}

class _LyricsActionState extends ConsumerState<_LyricsAction> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final canSearch =
        !_searching &&
        !widget.scriptIsBeingWritten &&
        widget.draft.video != null;
    return TextButton(
      style: _toolButtonStyle,
      onPressed: canSearch ? _replaceWithLyrics : null,
      child: Text(_searching ? 'Searching…' : 'Real lyrics'),
    );
  }

  Future<void> _replaceWithLyrics() async {
    final video = widget.draft.video;
    if (video == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(reelDraftProvider.notifier);
    setState(() => _searching = true);
    try {
      final transcript = await ref
          .read(lyricsServiceProvider)
          .replaceScript(video, widget.draft.language);
      controller.setTranscript(transcript);
      messenger.showSnackBar(const SnackBar(content: Text(_lyricsFound)));
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessageFor(error))));
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }
}

const _lyricsFound =
    'The lyrics from lrclib.net replaced the script. Line times follow the '
    'studio song, so check them in Fine-tune.';

/// FR-18: copy the script with a ready prompt for an AI agent, then paste
/// its corrected reply back.
class _AiFixActions extends ConsumerWidget {
  const _AiFixActions({
    required this.draft,
    required this.scriptIsBeingWritten,
  });

  final ReelDraft draft;
  final bool scriptIsBeingWritten;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUse = !scriptIsBeingWritten && draft.video != null;
    return Wrap(
      children: [
        TextButton(
          style: _toolButtonStyle,
          onPressed: canUse ? () => _copyForAi(context) : null,
          child: const Text('Copy for AI'),
        ),
        TextButton(
          style: _toolButtonStyle,
          onPressed: canUse ? () => _pasteFixed(context, ref) : null,
          child: const Text('Paste AI reply'),
        ),
      ],
    );
  }

  Future<void> _copyForAi(BuildContext context) async {
    final video = draft.video;
    final transcript = draft.transcript;
    if (video == null || transcript == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: scriptPromptFor(
          videoTitle: video.title,
          videoUrl: 'https://youtu.be/${video.videoId}',
          transcript: transcript,
        ),
      ),
    );
    messenger.showSnackBar(const SnackBar(content: Text(_copied)));
  }

  Future<void> _pasteFixed(BuildContext context, WidgetRef ref) async {
    final video = draft.video;
    final transcript = draft.transcript;
    if (video == null || transcript == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(reelDraftProvider.notifier);
    final editing = ref.read(scriptEditingServiceProvider);
    try {
      final pasted =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      final corrected = applyCorrectedScript(transcript, pasted);
      controller.correctTranscript(corrected.transcript);
      await editing.saveCorrected(video, draft.language, corrected.transcript);
      messenger.showSnackBar(
        SnackBar(content: Text(_pastedMessage(corrected))),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessageFor(error))));
    }
  }
}

const _copied =
    'Copied. Paste it into ChatGPT (or any AI that can search the web), copy '
    'its reply, then tap Paste AI reply.';

String _pastedMessage(CorrectedScript corrected) {
  final updated = 'Updated ${corrected.changedLines} lines.';
  if (corrected.uncertainRows.isEmpty) {
    return updated;
  }
  return '$updated The AI found no source for line '
      '${corrected.uncertainRows.join(', ')}: read it before you use it.';
}

/// FR-14: the script came from the saved scripts, not written just now.
class _SavedScriptBanner extends StatelessWidget {
  const _SavedScriptBanner({required this.savedAt, required this.onWriteAgain});

  final DateTime savedAt;
  final VoidCallback onWriteAgain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: HintText(
              'Using the saved script from '
              '${formatDayMonth(savedAt.toLocal())}',
            ),
          ),
          TextButton(
            onPressed: onWriteAgain,
            child: const Text('Write it again'),
          ),
        ],
      ),
    );
  }
}

/// "Still writing… NN %" above the button until the script is finished,
/// or why it stopped. A run that fails partway leaves its lines on screen,
/// so without this the script would look finished.
class _ScriptFooter extends StatelessWidget {
  const _ScriptFooter({
    required this.run,
    required this.onRetry,
    required this.child,
  });

  final AsyncValue<ScriptProgress> run;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (run.error case final error?) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  errorMessageFor(error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
          child,
        ],
      );
    }
    final progress = run.value;
    if (progress == null || progress.stage == ScriptStage.done) {
      return child;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HintText('Still writing… ${(progress.fraction * 100).round()} %'),
        child,
      ],
    );
  }
}

class _PickHint extends StatelessWidget {
  const _PickHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.textPrimary)),
    );
  }
}

class _ScriptLineTile extends StatelessWidget {
  const _ScriptLineTile({
    required this.line,
    required this.selection,
    required this.onTap,
  });

  final TranscriptLine line;
  final LineSelection selection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = selection.isHighlighted(line.index);
    final badge = _badgeFor(line.index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: highlighted,
        child: Material(
          color: highlighted
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: badge.isEmpty ? Colors.transparent : AppColors.accent,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        formatTimestamp(line.start),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      const Spacer(),
                      if (badge.isNotEmpty) _Badge(text: badge),
                    ],
                  ),
                  ScriptText(line.text, style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _badgeFor(int index) {
    return switch (selection) {
      RangeSelected(:final start, :final end)
          when start == index && end == index =>
        'Start · End',
      RangeSelected(:final start) when start == index => 'Start',
      RangeSelected(:final end) when end == index => 'End',
      StartSelected(:final start) when start == index => 'Start',
      _ => '',
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.onAccent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
