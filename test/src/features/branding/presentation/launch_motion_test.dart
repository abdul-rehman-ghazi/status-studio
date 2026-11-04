import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/branding/domain/logo_pose.dart';
import 'package:status_studio/src/features/branding/presentation/launch_motion.dart';

const _closeEnough = 1e-9;

/// Progress values across the whole animation, 0 to 1 inclusive.
final _timeline = [for (var step = 0; step <= 400; step++) step / 400];

void _expectRestPose(LogoPose pose) {
  expect(pose.bracketInset, closeTo(0, _closeEnough));
  for (final (index, halfLength) in pose.barHalfLengths.indexed) {
    expect(
      halfLength,
      closeTo(LogoPose.rest.barHalfLengths[index], _closeEnough),
    );
  }
}

void main() {
  test('first_frame_matches_the_native_splash', () {
    final frame = launchFrameAt(0);

    _expectRestPose(frame.logo.pose);
    expect(frame.logo.scale, 1);
    expect(frame.wordmark.opacity, 0);
    expect(frame.splashOpacity, 1);
  });

  test('bars_move_during_the_wave', () {
    final pose = launchFrameAt(0.15).logo.pose;

    final largestMove = [
      for (final (index, halfLength) in pose.barHalfLengths.indexed)
        (halfLength - LogoPose.rest.barHalfLengths[index]).abs(),
    ].reduce((a, b) => a > b ? a : b);
    expect(largestMove, greaterThan(2));
  });

  test('logo_is_back_at_rest_when_the_exit_starts', () {
    _expectRestPose(launchFrameAt(launchExitStart).logo.pose);
  });

  test('outer_bars_stay_clear_of_the_bracket_arms', () {
    final outerBarHalfLengths = [
      for (final progress in _timeline)
        for (final index in [0, 1, 3, 4])
          launchFrameAt(progress).logo.pose.barHalfLengths[index],
    ];

    expect(outerBarHalfLengths, everyElement(lessThanOrEqualTo(19)));
  });

  test('middle_bar_stays_inside_the_brackets', () {
    final middleBarHalfLengths = [
      for (final progress in _timeline)
        launchFrameAt(progress).logo.pose.barHalfLengths[2],
    ];

    expect(middleBarHalfLengths, everyElement(lessThanOrEqualTo(23)));
  });

  test('bars_never_vanish', () {
    final allHalfLengths = [
      for (final progress in _timeline)
        ...launchFrameAt(progress).logo.pose.barHalfLengths,
    ];

    expect(allHalfLengths, everyElement(greaterThanOrEqualTo(3)));
  });

  test('brackets_close_in_during_the_trim', () {
    final insets = [
      for (final progress in _timeline)
        launchFrameAt(progress).logo.pose.bracketInset,
    ];

    expect(insets.reduce((a, b) => a > b ? a : b), greaterThan(6));
  });

  test('brackets_never_touch_the_bars', () {
    final insets = [
      for (final progress in _timeline)
        launchFrameAt(progress).logo.pose.bracketInset,
    ];

    expect(insets, everyElement(lessThanOrEqualTo(maxBracketInset)));
  });

  test('wordmark_is_fully_shown_before_the_exit', () {
    final frame = launchFrameAt(launchExitStart);

    expect(frame.wordmark.opacity, 1);
    expect(frame.wordmark.lift, 0);
  });

  test('splash_is_transparent_at_the_end', () {
    expect(launchFrameAt(1).splashOpacity, 0);
  });
}
