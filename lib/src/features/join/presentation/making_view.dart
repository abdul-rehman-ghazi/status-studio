import 'package:flutter/material.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Review cuts while Make the clip runs (spec FR-37): the step, a bar and
/// Cancel, which is gone once the clip is being kept.
class MakingView extends StatelessWidget {
  const MakingView({required this.progress, required this.onCancel, super.key});

  final MakingProgress progress;
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
          Text(_stepOf(progress), textAlign: TextAlign.center),
          if (progress is DownloadingCut) ...[
            const SizedBox(height: 4),
            Center(child: HintText(_amountOf(progress))),
          ],
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _fractionOf(progress)),
          const SizedBox(height: 20),
          if (progress is! KeepingClip)
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

String _stepOf(MakingProgress progress) => switch (progress) {
  ReadingStreams() => "Reading the video's streams",
  DownloadingCut(:final number, :final count) =>
    'Downloading cut $number of $count',
  JoiningCuts() => 'Joining the cuts',
  KeepingClip() => 'Keeping the clip',
};

double? _fractionOf(MakingProgress progress) => switch (progress) {
  DownloadingCut() => progress.fraction,
  JoiningCuts(:final fraction) => fraction,
  ReadingStreams() || KeepingClip() => null,
};

/// "3.1 MB of 7.8 MB · 1.2 MB/s"; the size is known once the segment
/// indexes are read.
String _amountOf(DownloadingCut progress) {
  if (progress.totalBytes == 0) {
    return 'Reading the cut\'s place in the video';
  }
  return '${_megabytes(progress.receivedBytes)} of '
      '${_megabytes(progress.totalBytes)} · '
      '${_megabytes(progress.bytesPerSecond.round())}/s';
}

String _megabytes(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

/// A failed Make the clip (spec §8): its message, Try again, and Back to
/// the list.
class MakeFailureView extends StatelessWidget {
  const MakeFailureView({
    required this.failure,
    required this.onTryAgain,
    required this.onBack,
    super.key,
  });

  final Object failure;
  final VoidCallback onTryAgain;
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
          if (failure is OfflineException) ...[
            const SizedBox(height: 4),
            const Center(child: HintText('Finished cuts are kept.')),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: onTryAgain, child: const Text('Try again')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}
