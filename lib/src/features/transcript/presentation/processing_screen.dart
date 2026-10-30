import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  StreamSubscription<ScriptProgress>? _subscription;
  ScriptProgress? _progress;
  var _downloadsModel = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(reelDraftProvider);
    final video = draft.video;
    if (video == null) {
      throw StateError('Processing opened without a video.');
    }
    _subscription = ref
        .read(scriptPipelineProvider)
        .run(video, draft.language)
        .listen(_onProgress);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onProgress(ScriptProgress progress) {
    if (progress.stage == ScriptStage.done) {
      ref.read(reelDraftProvider.notifier).setTranscript(progress.transcript);
      context.pushReplacement(AppRoutes.script);
      return;
    }
    setState(() {
      _progress = progress;
      _downloadsModel |= progress.stage == ScriptStage.downloadingModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final progress = _progress;
    final stage = progress?.stage ?? ScriptStage.downloadingAudio;
    final steps = [
      if (_downloadsModel) _modelStep,
      ..._scriptSteps(draft.language, progress),
    ];
    return Scaffold(
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
          LinearProgressIndicator(value: progress?.fraction ?? 0),
          const SizedBox(height: 20),
          for (final step in steps) _StepRow(step: step, current: stage),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

typedef _Step = ({String label, String detail, ScriptStage stage});

const _Step _modelStep = (
  label: 'Downloading the speech model',
  detail: 'Needed once, then it works offline',
  stage: ScriptStage.downloadingModel,
);

List<_Step> _scriptSteps(ScriptLanguage language, ScriptProgress? progress) {
  return [
    (
      label: 'Downloading audio',
      detail: 'From YouTube, audio only',
      stage: ScriptStage.downloadingAudio,
    ),
    (
      label: 'Detecting the language',
      detail: _languageDetail(language, progress),
      stage: ScriptStage.detectingLanguage,
    ),
    (
      label: 'Writing the script',
      detail: 'Whisper, on your phone',
      stage: ScriptStage.transcribing,
    ),
    (
      label: 'Lining up timestamps',
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
  const _StepRow({required this.step, required this.current});

  final _Step step;
  final ScriptStage current;

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
              children: [Text(step.label), HintText(step.detail)],
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
