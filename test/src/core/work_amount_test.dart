import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/work_amount.dart';

const megabyte = 1000000;

WorkAmount bytes(int done, int total) =>
    WorkAmount(done: done, total: total, unit: WorkUnit.bytes);

WorkAmount audio(Duration done, Duration total) => WorkAmount(
  done: done.inMilliseconds,
  total: total.inMilliseconds,
  unit: WorkUnit.audioMilliseconds,
);

void main() {
  test('fraction_is_done_over_total', () {
    expect(bytes(25, 100).fraction, 0.25);
  });

  test('fraction_of_unknown_total_is_zero', () {
    expect(bytes(25, 0).fraction, 0);
  });

  test('rate_is_progress_since_the_first_sample_per_second', () {
    final rate = WorkRate.from(bytes(0, 100 * megabyte), Duration.zero);

    final perSecond = rate.perSecond(
      bytes(10 * megabyte, 100 * megabyte),
      const Duration(seconds: 4),
    );

    expect(perSecond, 2.5 * megabyte);
  });

  test('rate_is_unknown_until_time_has_passed', () {
    final rate = WorkRate.from(bytes(0, 100), const Duration(seconds: 3));

    expect(rate.perSecond(bytes(10, 100), const Duration(seconds: 3)), isNull);
  });

  test('bytes_line_shows_percent_sizes_and_speed', () {
    final line = workLine(
      bytes(220 * megabyte, 487 * megabyte),
      perSecond: 3.2 * megabyte,
    );

    expect(line, '45 % · 220 of 487 MB · 3.2 MB/s');
  });

  test('small_sizes_and_slow_speeds_keep_a_decimal_and_use_kb', () {
    final line = workLine(bytes(1100000, 3300000), perSecond: 200000);

    expect(line, '33 % · 1.1 of 3.3 MB · 200 KB/s');
  });

  test('audio_line_shows_percent_lengths_and_speed', () {
    final line = workLine(
      audio(const Duration(minutes: 3), const Duration(minutes: 9, seconds: 8)),
      perSecond: 1300,
    );

    expect(line, '33 % · 3:00 of 9:08 · 1.3× real time');
  });

  test('line_without_a_speed_yet_leaves_it_out', () {
    expect(workLine(bytes(0, 487 * megabyte)), '0 % · 0 of 487 MB');
  });
}
