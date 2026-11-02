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

  test('percent_is_the_fraction_rounded', () {
    expect(workPercent(bytes(220 * megabyte, 487 * megabyte)), '45 %');
  });

  test('bytes_done_line_shows_sizes_and_speed', () {
    final line = workDoneLine(
      bytes(220 * megabyte, 487 * megabyte),
      perSecond: 3.2 * megabyte,
    );

    expect(line, '220 of 487 MB · 3.2 MB/s');
  });

  test('small_sizes_and_slow_speeds_keep_a_decimal_and_use_kb', () {
    final line = workDoneLine(bytes(1100000, 3300000), perSecond: 200000);

    expect(line, '1.1 of 3.3 MB · 200 KB/s');
  });

  test('audio_done_line_shows_lengths_and_speed', () {
    final line = workDoneLine(
      audio(const Duration(minutes: 3), const Duration(minutes: 9, seconds: 8)),
      perSecond: 1300,
    );

    expect(line, '3:00 of 9:08 · 1.3× real time');
  });

  test('done_line_without_a_speed_yet_leaves_it_out', () {
    expect(workDoneLine(bytes(0, 487 * megabyte)), '0 of 487 MB');
  });

  test('unknown_total_shows_only_what_is_done', () {
    expect(workDoneLine(bytes(12 * megabyte, 0)), '12 MB');
  });

  test('time_left_is_the_remaining_work_at_the_current_speed', () {
    final timeLeft = workTimeLeft(
      bytes(220 * megabyte, 487 * megabyte),
      perSecond: 3.2 * megabyte,
    );

    expect(timeLeft, '1:24 left');
  });

  test('audio_time_left_uses_the_real_time_speed', () {
    final timeLeft = workTimeLeft(
      audio(const Duration(minutes: 3), const Duration(minutes: 9, seconds: 8)),
      perSecond: 1300,
    );

    expect(timeLeft, '4:44 left');
  });

  test('time_left_rounds_up_so_it_never_reads_zero_too_early', () {
    expect(workTimeLeft(bytes(990, 1000), perSecond: 100), '0:01 left');
  });

  test('time_left_can_be_estimated_while_work_remains_at_a_speed', () {
    expect(canEstimateTimeLeft(bytes(220, 487), perSecond: 1), isTrue);
  });

  test('finished_step_has_no_time_left', () {
    expect(canEstimateTimeLeft(bytes(487, 487), perSecond: 1), isFalse);
  });

  test('stalled_step_has_no_time_left', () {
    expect(canEstimateTimeLeft(bytes(220, 487), perSecond: 0), isFalse);
  });

  test('unknown_total_has_no_time_left', () {
    expect(canEstimateTimeLeft(bytes(12, 0), perSecond: 1), isFalse);
  });
}
