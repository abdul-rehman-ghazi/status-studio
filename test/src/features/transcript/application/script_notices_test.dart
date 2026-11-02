import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/application/script_notices.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  const notices = ScriptNotices(sampleVideo);

  test('script_progress_notice_names_the_step_and_video', () {
    final notice = notices.progress(
      ScriptProgress(
        stage: ScriptStage.transcribing,
        fraction: 0.456,
        transcript: fixture,
      ),
    );

    expect(
      notice,
      const ProgressNotice(
        title: 'Writing the script',
        text: 'Sample video',
        percent: 46,
      ),
    );
  });

  test('script_starting_notice_names_the_video_at_zero', () {
    expect(
      notices.starting,
      const ProgressNotice(
        title: 'Getting the script',
        text: 'Sample video',
        percent: 0,
      ),
    );
  });

  test('script_done_notice_says_ready', () {
    expect(
      notices.done,
      const ResultNotice(title: 'Script ready', text: 'Sample video'),
    );
  });

  test('script_failed_notice_shows_the_error_message', () {
    expect(
      notices.failed(const OfflineException('no route')),
      const ResultNotice(
        title: 'Script stopped',
        text: "You're offline. Connect and try again.",
      ),
    );
  });
}
