import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/export/application/export_notices.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/routing/app_router.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  StreamSubscription<RenderProgress>? _subscription;
  var _fraction = 0.0;

  /// Why the last render failed (spec §8); set until Retry.
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _startRender();
  }

  /// Keeps rendering when the user leaves the app or locks the phone
  /// (FR-16).
  void _startRender() {
    final draft = ref.read(reelDraftProvider);
    _subscription = ref
        .read(backgroundWorkProvider)
        .keepRunning(
          ref.read(rendererProvider).render(draft),
          ExportNotices(draft.video?.title ?? ''),
        )
        .listen(
          _onProgress,
          onError: (Object error) => setState(() => _failure = error),
        );
  }

  void _retry() {
    setState(() {
      _failure = null;
      _fraction = 0;
    });
    _startRender();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onProgress(RenderProgress progress) {
    switch (progress) {
      case RenderRunning(:final fraction):
        setState(() => _fraction = fraction);
      case RenderFinished(:final videoPath):
        unawaited(_keepAndOpenDone(videoPath));
    }
  }

  /// Adds the reel to Recent (FR-11), then opens Done for it. Done reads
  /// the reel from Recent, so a reel that couldn't be recorded is a
  /// failure the user can retry.
  Future<void> _keepAndOpenDone(String videoPath) async {
    final draft = ref.read(reelDraftProvider);
    final size = outputSizeFor(draft.frame, previewSourceSize(ref, draft));
    try {
      final reel = await ref
          .read(recentReelsProvider.notifier)
          .keep(videoPath, draft, size);
      // The reel is made, so the kept fine-tune is spent (spec FR-24).
      unawaited(ref.read(fineTuneDraftSaverProvider).discard(draft));
      if (mounted) {
        context.pushReplacement(AppRoutes.doneFor(reel.id));
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _failure = error);
      }
    }
  }

  Future<void> _cancel() async {
    // Stop listening first so a late RenderFinished can't open Done.
    unawaited(_subscription?.cancel());
    _subscription = null;
    await ref.read(rendererProvider).cancel();
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // System back must go through Cancel so the render really stops (FR-9).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_cancel());
        }
      },
      child: _buildScaffold(context),
    );
  }

  /// Cancel while rendering; Retry and Back once it has failed.
  Widget _actions() {
    if (_failure == null) {
      return OutlinedButton(onPressed: _cancel, child: const Text('Cancel'));
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(onPressed: _cancel, child: const Text('Back')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(onPressed: _retry, child: const Text('Retry')),
        ),
      ],
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final percent = (_fraction * 100).round();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$percent%',
              textAlign: TextAlign.center,
              style: textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _fraction),
            const SizedBox(height: 24),
            if (_failure case final failure?)
              Text(
                errorMessageFor(failure),
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            else
              Text(
                'Rendering your reel',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            for (final line in _summaryLines(
              ref.watch(reelDraftProvider),
              previewSourceSize(ref, ref.watch(reelDraftProvider)),
            ))
              Center(child: HintText(line)),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(child: _actions()),
    );
  }
}

List<String> _summaryLines(ReelDraft draft, OutputSize sourceSize) {
  final output = outputSizeFor(draft.frame, sourceSize);
  return [
    if (draft.clip case final clip?)
      'Clip ${formatClipTime(clip.start)} – ${formatClipTime(clip.end)}',
    '${_frameSummary(draft.frame)} at $output',
    'Caption in ${_captionLanguage(draft)}',
    'App name and logo',
  ];
}

String _frameSummary(FrameSettings frame) {
  return switch (frame) {
    FrameSettings(preset: AspectPreset.free) => 'Free crop',
    FrameSettings(preset: AspectPreset.landscape16x9) => 'Original frame',
    FrameSettings(fill: FillMode.crop) => 'Cropped',
    FrameSettings(fill: FillMode.blur) => 'Blurred background',
  };
}

String _captionLanguage(ReelDraft draft) {
  final transcriptLanguage = ScriptLanguage.values
      .where(
        (language) => language.whisperCode == draft.transcript?.languageCode,
      )
      .firstOrNull;
  return switch (draft.caption.variant) {
    CaptionVariant.original => transcriptLanguage?.label ?? 'the original',
    CaptionVariant.roman => 'Roman Urdu',
    CaptionVariant.english => 'English',
  };
}
