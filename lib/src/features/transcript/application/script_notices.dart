import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';

/// The notifications for a script run (spec FR-16).
class ScriptNotices implements JobNotices<ScriptProgress> {
  const ScriptNotices(this.video);

  final SourceVideo video;

  @override
  BackgroundJob get job => BackgroundJob.script;

  @override
  ProgressNotice progress(ScriptProgress event) => ProgressNotice(
    title: event.stage.label,
    text: video.title,
    percent: (event.fraction * 100).round(),
  );

  @override
  ResultNotice get done =>
      ResultNotice(title: 'Script ready', text: video.title);

  @override
  ResultNotice failed(Object error) =>
      ResultNotice(title: 'Script stopped', text: errorMessageFor(error));
}
