import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_consent_screen.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Whether the reel's script is being written now (spec FR-3).
bool isScriptBeingWritten(AsyncValue<ScriptProgress?> run) {
  if (run.hasError) {
    return false;
  }
  if (run.isLoading) {
    return true;
  }
  final progress = run.value;
  return progress != null && progress.stage != ScriptStage.done;
}

/// The script run on Fine-tune · Lyrics (spec FR-3, M30): the step under
/// way with how much is done and Cancel, or why it stopped with what to do
/// (§8). Nothing while no run is going and none has failed.
class ScriptRunSection extends ConsumerStatefulWidget {
  const ScriptRunSection({super.key});

  @override
  ConsumerState<ScriptRunSection> createState() => _ScriptRunSectionState();
}

class _ScriptRunSectionState extends ConsumerState<ScriptRunSection> {
  /// Measures each step's speed from when this section first saw it.
  final _clock = Stopwatch()..start();
  final _amounts = <ScriptStage, _StepAmounts>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual(scriptProgressProvider, (previous, next) {
      _record(next.value);
      _askConsentOnArrival(previous, next);
    }, fireImmediately: true);
  }

  /// The first upload needs the user's OK (FR-30): the run stops before
  /// any audio work, and the consent screen opens by itself, once per
  /// failure. "Continue" on the failure opens it again.
  void _askConsentOnArrival(
    AsyncValue<ScriptProgress?>? previous,
    AsyncValue<ScriptProgress?> next,
  ) {
    if (next.error is! NoGroqConsentException ||
        previous?.error is NoGroqConsentException) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_askConsentThenRetry(context, ref));
      }
    });
  }

  void _record(ScriptProgress? progress) {
    final step = progress?.step;
    if (progress == null || step == null) {
      return;
    }
    final at = _clock.elapsed;
    final seen = _amounts[progress.stage];
    _amounts[progress.stage] = (
      rate: seen?.rate ?? WorkRate.from(step, at),
      latest: step,
      latestAt: at,
    );
  }

  _StepReading? _readingFor(ScriptStage stage) {
    final amounts = _amounts[stage];
    if (amounts == null) {
      return null;
    }
    return (
      amount: amounts.latest,
      perSecond: amounts.rate.perSecond(amounts.latest, amounts.latestAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(scriptProgressProvider);
    if (run.error case final error?) {
      return _RunFailed(error: error);
    }
    if (!isScriptBeingWritten(run)) {
      return const SizedBox.shrink();
    }
    final progress = run.value;
    final stage = progress?.stage ?? ScriptStage.preparingAudio;
    final language = ref.watch(reelDraftProvider.select((d) => d.language));
    final step = _scriptSteps(
      language,
      progress,
    ).firstWhere((candidate) => candidate.stage == stage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress?.fraction ?? 0),
        Row(
          children: [
            Expanded(
              child: _StepRow(
                step: step,
                current: stage,
                reading: _readingFor(stage),
              ),
            ),
            TextButton(
              onPressed: ref.read(scriptProgressProvider.notifier).cancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

/// What a failed run offers, spec §8.
enum _FailureAction {
  retry('Retry'),
  consent('Continue'),
  settings('Settings'),
  dismiss('Dismiss'),
  anotherLanguage('Try another language');

  const _FailureAction(this.label);

  final String label;
}

List<_FailureAction> _actionsFor(Object error) {
  return switch (error) {
    NoSpeechFoundException() => [_FailureAction.anotherLanguage],
    InsufficientStorageException() => const [],
    NoGroqConsentException() => const [
      _FailureAction.consent,
      _FailureAction.dismiss,
    ],
    NoGroqKeyException() || GroqKeyRejectedException() => const [
      _FailureAction.settings,
      _FailureAction.dismiss,
    ],
    GroqRateLimitedException() => const [_FailureAction.dismiss],
    GroqFailedException() || GroqOfflineException() => const [
      _FailureAction.retry,
      _FailureAction.dismiss,
    ],
    _ => const [_FailureAction.retry, _FailureAction.dismiss],
  };
}

/// Spec §8 message for a failed run, with the actions it offers.
class _RunFailed extends ConsumerWidget {
  const _RunFailed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          errorMessageFor(error),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 16),
        for (final action in _actionsFor(error))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _perform(action, context, ref),
              child: Text(action.label),
            ),
          ),
      ],
    );
  }

  void _perform(_FailureAction action, BuildContext context, WidgetRef ref) {
    switch (action) {
      case _FailureAction.retry:
        _retryScript(ref);
      case _FailureAction.consent:
        unawaited(_askConsentThenRetry(context, ref));
      case _FailureAction.settings:
        context.push(AppRoutes.groqSettings);
      // The Get card comes back, with its language choice.
      case _FailureAction.dismiss || _FailureAction.anotherLanguage:
        ref.read(scriptProgressProvider.notifier).cancel();
    }
  }
}

void _retryScript(WidgetRef ref) {
  final draft = ref.read(reelDraftProvider);
  if (draft.video case final video?) {
    ref.read(scriptProgressProvider.notifier).start(video, draft.language);
  }
}

/// "Not now" leaves the failure on screen, with Continue and Back.
Future<void> _askConsentThenRetry(BuildContext context, WidgetRef ref) async {
  if (await askForGroqConsent(context)) {
    _retryScript(ref);
  }
}

typedef _Step = ({String label, String detail, ScriptStage stage});

/// A step's first and latest amounts in this run.
typedef _StepAmounts = ({WorkRate rate, WorkAmount latest, Duration latestAt});

/// How much of a step is done, and how fast, as last measured.
typedef _StepReading = ({WorkAmount amount, double? perSecond});

List<_Step> _scriptSteps(ScriptLanguage language, ScriptProgress? progress) {
  return [
    (
      label: ScriptStage.preparingAudio.label,
      detail: 'From your video, on this phone',
      stage: ScriptStage.preparingAudio,
    ),
    (
      label: ScriptStage.detectingLanguage.label,
      detail: _languageDetail(language, progress),
      stage: ScriptStage.detectingLanguage,
    ),
    (
      label: ScriptStage.transcribing.label,
      detail: 'Groq, in the cloud',
      stage: ScriptStage.transcribing,
    ),
    (
      label: ScriptStage.done.label,
      detail: 'So every line knows when it is said',
      stage: ScriptStage.done,
    ),
  ];
}

String _languageDetail(ScriptLanguage language, ScriptProgress? progress) {
  if (language != ScriptLanguage.auto) {
    return 'Set to ${language.label}';
  }
  final detectedCode = progress?.transcript.languageCode;
  final detected = ScriptLanguage.values
      .where((candidate) => candidate.whisperCode == detectedCode)
      .firstOrNull;
  final isPastDetection =
      (progress?.stage.index ?? 0) > ScriptStage.detectingLanguage.index;
  if (detected == null || !isPastDetection) {
    return 'Automatic';
  }
  return 'Found: ${detected.label}';
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.current,
    required this.reading,
  });

  final _Step step;
  final ScriptStage current;

  /// Once the step has reported how much is done.
  final _StepReading? reading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox.square(dimension: 24, child: _statusIcon(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label),
                HintText(step.detail),
                if (reading case final reading?) _StepAmount(reading: reading),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(BuildContext context) {
    if (current.index > step.stage.index) {
      return Icon(Icons.check_circle, color: context.palette.accent);
    }
    if (current == step.stage) {
      return const Padding(
        padding: EdgeInsets.all(3),
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return Icon(Icons.radio_button_unchecked, color: context.palette.textMuted);
  }
}

/// The step's bar and percent, then done of total and speed with the time
/// left beside them.
class _StepAmount extends StatelessWidget {
  const _StepAmount({required this.reading});

  final _StepReading reading;

  @override
  Widget build(BuildContext context) {
    final amount = reading.amount;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (amount.knowsTotal) _PercentBar(amount: amount),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: HintText(
                  workDoneLine(amount, perSecond: reading.perSecond),
                ),
              ),
              if (reading.perSecond case final perSecond?
                  when canEstimateTimeLeft(amount, perSecond: perSecond))
                HintText(workTimeLeft(amount, perSecond: perSecond)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PercentBar extends StatelessWidget {
  const _PercentBar({required this.amount});

  final WorkAmount amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: amount.fraction,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        HintText(workPercent(amount)),
      ],
    );
  }
}
