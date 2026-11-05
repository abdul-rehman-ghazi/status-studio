import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Shows the script run that the previous screen started.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  var _leaving = false;

  /// Measures each step's speed from when this screen first saw it.
  final _clock = Stopwatch()..start();
  final _amounts = <ScriptStage, _StepAmounts>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      scriptProgressProvider,
      (_, next) => _record(next.value),
      fireImmediately: true,
    );
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

  Map<ScriptStage, _StepReading> get _readings => {
    for (final MapEntry(key: stage, value: amounts) in _amounts.entries)
      stage: (
        amount: amounts.latest,
        perSecond: amounts.rate.perSecond(amounts.latest, amounts.latestAt),
      ),
  };

  /// Checked on every build, not only on change: a saved script can be
  /// done before this screen is even built.
  void _openScriptIfDone(AsyncValue<ScriptProgress> run) {
    if (_leaving) {
      return;
    }
    if (run case AsyncData(value: ScriptProgress(stage: ScriptStage.done))) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.pushReplacement(AppRoutes.script);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final run = ref.watch(scriptProgressProvider);
    _openScriptIfDone(run);
    return PopScope(
      // System back leaves the run as surely as Cancel does.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(scriptProgressProvider.notifier).cancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Working'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Writing the script',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (draft.video case final video?) _VideoLine(video: video),
            const SizedBox(height: 20),
            if (run.error case final error?)
              _RunFailed(error: error)
            else
              _RunSteps(
                steps: _scriptSteps(draft.language, run.value),
                progress: run.value,
                readings: _readings,
              ),
          ],
        ),
        bottomNavigationBar: BottomAction(
          child: _bottomButton(context, ref, run.value),
        ),
      ),
    );
  }

  /// Once a line exists the user can start picking (FR-3 progressive).
  Widget _bottomButton(
    BuildContext context,
    WidgetRef ref,
    ScriptProgress? progress,
  ) {
    if (progress != null && progress.transcript.lines.isNotEmpty) {
      return FilledButton(
        onPressed: () => context.pushReplacement(AppRoutes.script),
        child: const Text('Start picking lines'),
      );
    }
    return OutlinedButton(
      onPressed: () {
        ref.read(scriptProgressProvider.notifier).cancel();
        context.pop();
      },
      child: const Text('Cancel'),
    );
  }
}

class _RunSteps extends StatelessWidget {
  const _RunSteps({
    required this.steps,
    required this.progress,
    required this.readings,
  });

  final List<_Step> steps;
  final ScriptProgress? progress;

  /// Only the steps that report how much is done have one.
  final Map<ScriptStage, _StepReading> readings;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final stage = progress?.stage ?? ScriptStage.preparingAudio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress?.fraction ?? 0),
        const SizedBox(height: 20),
        for (final step in steps)
          _StepRow(step: step, current: stage, reading: readings[step.stage]),
      ],
    );
  }
}

/// What a failed run offers, spec §8.
enum _FailureAction {
  retry('Retry'),
  settings('Settings'),
  back('Back'),
  anotherLanguage('Try another language');

  const _FailureAction(this.label);

  final String label;
}

List<_FailureAction> _actionsFor(Object error) {
  return switch (error) {
    NoSpeechFoundException() => [_FailureAction.anotherLanguage],
    InsufficientStorageException() => const [],
    NoGroqKeyException() || GroqKeyRejectedException() => const [
      _FailureAction.settings,
      _FailureAction.back,
    ],
    GroqRateLimitedException() => const [_FailureAction.back],
    GroqFailedException() ||
    GroqOfflineException() => const [_FailureAction.retry, _FailureAction.back],
    _ => const [_FailureAction.retry],
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
        _retry(ref);
      case _FailureAction.settings:
        context.push(AppRoutes.settings);
      case _FailureAction.back || _FailureAction.anotherLanguage:
        context.pop();
    }
  }

  void _retry(WidgetRef ref) {
    final draft = ref.read(reelDraftProvider);
    if (draft.video case final video?) {
      ref.read(scriptProgressProvider.notifier).start(video, draft.language);
    }
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

class _VideoLine extends StatelessWidget {
  const _VideoLine({required this.video});

  final SourceVideo video;

  @override
  Widget build(BuildContext context) {
    return HintText('${video.title} · ${formatTimestamp(video.duration)}');
  }
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
          SizedBox.square(dimension: 24, child: _statusIcon()),
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

  Widget _statusIcon() {
    if (current.index > step.stage.index) {
      return const Icon(Icons.check_circle, color: AppColors.accent);
    }
    if (current == step.stage) {
      return const Padding(
        padding: EdgeInsets.all(3),
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return const Icon(Icons.radio_button_unchecked, color: AppColors.textMuted);
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
