import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';

/// The notifications for an export (spec FR-16).
class ExportNotices implements JobNotices<RenderProgress> {
  const ExportNotices(this.videoTitle);

  final String videoTitle;

  @override
  BackgroundJob get job => BackgroundJob.export;

  @override
  ProgressNotice progress(RenderProgress event) => ProgressNotice(
    title: 'Rendering your reel',
    text: videoTitle,
    percent: switch (event) {
      RenderRunning(:final fraction) => (fraction * 100).round(),
      RenderFinished() => 100,
    },
  );

  @override
  ResultNotice get done =>
      const ResultNotice(title: 'Reel ready', text: 'Tap to save or share it.');

  @override
  ResultNotice failed(Object error) =>
      ResultNotice(title: 'Export stopped', text: errorMessageFor(error));
}
