import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/domain/lines_in_clip.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/presentation/caption_style_sheet.dart';
import 'package:status_studio/src/features/transcript/application/groq_script_fix_service.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_consent_screen.dart';
import 'package:status_studio/src/features/transcript/presentation/script_run_section.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// The lyrics' tools above the lines on Fine-tune · Lyrics (spec FR-7,
/// FR-14, FR-19, M30): Aa Style, Fix with Groq and Get again, and where the
/// lines came from when they are a saved script.
class LyricsTools extends ConsumerWidget {
  const LyricsTools({required this.onGetAgain, super.key});

  final VoidCallback onGetAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reelDraftProvider);
    final run = ref.watch(scriptProgressProvider);
    final isWriting = isScriptBeingWritten(run);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              style: _toolButtonStyle,
              onPressed: () => unawaited(showCaptionStyleSheet(context)),
              icon: const Icon(Icons.text_fields),
              label: const Text('Style'),
            ),
            _GroqFixAction(draft: draft, scriptIsBeingWritten: isWriting),
            TextButton.icon(
              style: _toolButtonStyle,
              onPressed: isWriting ? null : onGetAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('Get again'),
            ),
          ],
        ),
        if (run.value?.savedAt case final savedAt?)
          HintText(
            'Using the saved script from ${formatDayMonth(savedAt.toLocal())}',
          ),
      ],
    );
  }
}

/// Compact, so the tools fit one row and the lines keep their room.
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
    final canFix =
        !widget.scriptIsBeingWritten &&
        widget.draft.video != null &&
        widget.draft.transcript?.lines.isNotEmpty == true;
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
            selection: _linesToFix(draft, transcript),
          );
      if (run != _wantedRun) {
        return;
      }
      controller.correctTranscript(corrected.transcript);
      await editing.saveCorrected(video, draft.language, corrected.transcript);
      messenger.showSnackBar(
        SnackBar(content: Text(_correctedMessage(corrected))),
      );
    } on NoGroqConsentException {
      if (run == _wantedRun && mounted) {
        unawaited(_askConsentThenFix());
      }
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

  /// Nothing was sent (FR-30); "Not now" leaves the lines as they are.
  Future<void> _askConsentThenFix() async {
    if (await askForGroqConsent(context) && mounted) {
      await _fix();
    }
  }
}

/// The lines inside the clip, so trimming the clip on Fine-tune is how a
/// long script gets short enough for the AI (spec FR-19).
RangeSelected _linesToFix(ReelDraft draft, Transcript transcript) {
  final clip = draft.clip;
  return clip == null
      ? RangeSelected(0, transcript.lines.length - 1)
      : linesInClip(transcript, clip);
}

SnackBar _fixFailedSnackBar(Object error, GoRouter router) {
  if (error is NoGroqKeyException) {
    return SnackBar(
      content: const Text('Fixing a script needs a free Groq key.'),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: () => router.push(AppRoutes.groqSettings),
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
