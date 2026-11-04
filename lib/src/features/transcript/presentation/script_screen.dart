import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/application/groq_script_fix_service.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/application/script_opening_notice.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
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
        stepLabel: 'Step 2 of 5',
      ),
      body: Column(
        children: [
          const _OpeningNotice(),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _GroqFixAction(
                draft: draft,
                scriptIsBeingWritten: _isBeingWritten(
                  ref.watch(scriptProgressProvider),
                ),
              ),
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

/// Shows, once, why Script opened instead of a kept fine-tune (spec FR-24).
class _OpeningNotice extends ConsumerStatefulWidget {
  const _OpeningNotice();

  @override
  ConsumerState<_OpeningNotice> createState() => _OpeningNoticeState();
}

class _OpeningNoticeState extends ConsumerState<_OpeningNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingNotice());
  }

  void _showPendingNotice() {
    final pending = ref.read(scriptOpeningNoticeProvider);
    if (!mounted || pending == null) {
      return;
    }
    ref.read(scriptOpeningNoticeProvider.notifier).clear();
    final videoId = ref.read(reelDraftProvider).video?.videoId;
    if (pending.videoId != videoId) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(pending.notice.message)));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

/// FR-19: Groq's web-search model fixes the script, with the saved key.
class _GroqFixAction extends ConsumerStatefulWidget {
  const _GroqFixAction({
    required this.draft,
    required this.scriptIsBeingWritten,
  });

  final ReelDraft draft;
  final bool scriptIsBeingWritten;

  @override
  ConsumerState<_GroqFixAction> createState() => _GroqFixActionState();
}

class _GroqFixActionState extends ConsumerState<_GroqFixAction> {
  bool _running = false;

  /// The run whose reply is still wanted; Cancel and leaving move it on.
  int _wantedRun = 0;

  @override
  void dispose() {
    _wantedRun++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          TextButton(
            style: _toolButtonStyle,
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      );
    }
    final canFix = !widget.scriptIsBeingWritten && widget.draft.video != null;
    return TextButton(
      style: _toolButtonStyle,
      onPressed: canFix ? _fix : null,
      child: const Text('Fix with Groq'),
    );
  }

  void _setRunning(bool running) => setState(() => _running = running);

  void _cancel() {
    _wantedRun++;
    _setRunning(false);
  }

  Future<void> _fix() async {
    final draft = widget.draft;
    final video = draft.video;
    final transcript = draft.transcript;
    if (video == null || transcript == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final controller = ref.read(reelDraftProvider.notifier);
    final editing = ref.read(scriptEditingServiceProvider);
    final run = ++_wantedRun;
    _setRunning(true);
    try {
      final corrected = await ref
          .read(groqScriptFixServiceProvider)
          .fix(
            video: video,
            transcript: transcript,
            selection: draft.selection,
          );
      if (run != _wantedRun) {
        return;
      }
      controller.correctTranscript(corrected.transcript);
      await editing.saveCorrected(video, draft.language, corrected.transcript);
      messenger.showSnackBar(
        SnackBar(content: Text(_correctedMessage(corrected))),
      );
    } on Exception catch (error) {
      if (run == _wantedRun) {
        messenger.showSnackBar(_fixFailedSnackBar(error, router));
      }
    } finally {
      if (run == _wantedRun && mounted) {
        _setRunning(false);
      }
    }
  }
}

SnackBar _fixFailedSnackBar(Object error, GoRouter router) {
  if (error is NoGroqKeyException) {
    return SnackBar(
      content: const Text('Fixing a script needs a free Groq key.'),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: () => router.push(AppRoutes.settings),
      ),
    );
  }
  if (error is NoScriptRowsException) {
    return const SnackBar(
      content: Text("Groq's reply had no script lines. Try again."),
    );
  }
  if (error is GroqFailedException) {
    return const SnackBar(content: Text("Groq couldn't fix this script."));
  }
  return SnackBar(content: Text(errorMessageFor(error)));
}

String _correctedMessage(CorrectedScript corrected) {
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
