import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';

/// Downloading takes most of a run; the join the rest.
const _downloadShare = 0.8;

/// The notifications for Make the clip (spec FR-16, FR-37).
class ClipNotices implements JobNotices<MakingProgress> {
  const ClipNotices(this.topic);

  /// The clip's name until it is kept.
  final String topic;

  @override
  BackgroundJob get job => BackgroundJob.clip;

  @override
  ProgressNotice get starting => ProgressNotice(
    title: "Reading the video's streams",
    text: topic,
    percent: 0,
  );

  @override
  ProgressNotice progress(MakingProgress event) => switch (event) {
    ReadingStreams() => starting,
    DownloadingCut(:final number, :final count) => ProgressNotice(
      title: 'Downloading cut $number of $count',
      text: topic,
      percent: _percent((number - 1 + event.fraction) / count * _downloadShare),
    ),
    JoiningCuts(:final fraction) => ProgressNotice(
      title: 'Joining the cuts',
      text: topic,
      percent: _percent(_downloadShare + fraction * (1 - _downloadShare)),
    ),
    KeepingClip() => ProgressNotice(
      title: 'Keeping the clip',
      text: topic,
      percent: 100,
    ),
  };

  @override
  ResultNotice get done =>
      const ResultNotice(title: 'Clip ready', text: 'Tap to crop it.');

  @override
  ResultNotice failed(Object error) =>
      ResultNotice(title: 'Clip stopped', text: errorMessageFor(error));
}

int _percent(double fraction) => (fraction.clamp(0, 1) * 100).round();
