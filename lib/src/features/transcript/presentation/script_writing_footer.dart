import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_consent_screen.dart';

/// "Still writing… NN %" above the button until the script is finished,
/// or why it stopped. A run that fails partway leaves its lines on screen,
/// so without this the script would look finished.
class ScriptWritingFooter extends ConsumerWidget {
  const ScriptWritingFooter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(scriptProgressProvider);
    if (run.error case final error?) {
      // Consent withdrawn in Settings stops the run at its next piece
      // (FR-30); Retry asks for it again rather than failing the same way.
      void onRetry() => error is NoGroqConsentException
          ? unawaited(_askConsentThenResume(context, ref))
          : _resume(ref);
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

Future<void> _askConsentThenResume(BuildContext context, WidgetRef ref) async {
  if (await askForGroqConsent(context)) {
    _resume(ref);
  }
}

/// Starts the run again; Groq resumes from its saved progress.
void _resume(WidgetRef ref) {
  final draft = ref.read(reelDraftProvider);
  if (draft.video case final video?) {
    ref.read(scriptProgressProvider.notifier).start(video, draft.language);
  }
}
