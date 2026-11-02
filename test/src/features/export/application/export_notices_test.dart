import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';
import 'package:status_studio/src/features/export/application/export_notices.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';

void main() {
  const notices = ExportNotices('Sample video');

  test('export_progress_notice_shows_the_percent', () {
    expect(
      notices.progress(const RenderRunning(0.25)),
      const ProgressNotice(
        title: 'Rendering your reel',
        text: 'Sample video',
        percent: 25,
      ),
    );
  });

  test('export_starting_notice_is_at_zero', () {
    expect(notices.starting.percent, 0);
  });

  test('finished_render_is_at_one_hundred_percent', () {
    expect(notices.progress(const RenderFinished('reel.mp4')).percent, 100);
  });

  test('export_done_notice_says_ready', () {
    expect(
      notices.done,
      const ResultNotice(title: 'Reel ready', text: 'Tap to save or share it.'),
    );
  });

  test('export_failed_notice_shows_the_error_message', () {
    expect(
      notices.failed(const RenderFailedException('codec failed')),
      const ResultNotice(
        title: 'Export stopped',
        text: "Couldn't make the reel.",
      ),
    );
  });
}
