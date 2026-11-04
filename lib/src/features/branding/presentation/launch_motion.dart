import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:status_studio/src/features/branding/domain/logo_pose.dart';

/// One frame of the launch animation (spec FR-20).
class LaunchFrame {
  const LaunchFrame({
    required this.logo,
    required this.wordmark,
    required this.splashOpacity,
  });

  final LogoFrame logo;
  final WordmarkFrame wordmark;
  final double splashOpacity;
}

class LogoFrame {
  const LogoFrame({required this.pose, required this.scale});

  final LogoPose pose;

  /// 1 is the native splash's 144 dp.
  final double scale;
}

class WordmarkFrame {
  const WordmarkFrame({required this.opacity, required this.lift});

  final double opacity;

  /// Logical pixels still to rise before the wordmark is in place.
  final double lift;
}

/// The furthest the brackets move in: the left bracket's stroke then ends at
/// x 34, short of the first bar's edge at 35.75.
const maxBracketInset = 7.0;

/// From here on the logo is at rest and only the splash fades.
const launchExitStart = 0.82;

const _waveTiming = Interval(0, 0.5);
const _trimTiming = Interval(0.38, 0.68, curve: Curves.easeInOut);
const _wordmarkTiming = Interval(0.45, 0.7, curve: Curves.easeOutCubic);
const _exitTiming = Interval(launchExitStart, 1, curve: Curves.easeIn);

/// Outer bars sit under the bracket arms (y 24–27) once the brackets close
/// in, so they stop short of y 31; the middle bar never does.
const _barMaxHalfLengths = [19.0, 19.0, 23.0, 19.0, 19.0];
const _barMinHalfLength = 3.0;
const _waveCycles = 2;
const _barPhaseStep = 1.1;
const _wordmarkTravel = 12.0;
const _exitGrowth = 0.12;

LaunchFrame launchFrameAt(double progress) {
  final exit = _exitTiming.transform(progress);
  return LaunchFrame(
    logo: LogoFrame(
      pose: LogoPose(
        bracketInset: _bracketInsetAt(progress),
        barHalfLengths: _barHalfLengthsAt(progress),
      ),
      scale: 1 + _exitGrowth * exit,
    ),
    wordmark: _wordmarkAt(progress),
    splashOpacity: 1 - exit,
  );
}

double _bracketInsetAt(double progress) =>
    maxBracketInset * math.sin(math.pi * _trimTiming.transform(progress));

/// Each bar swings like a voice level, out of step with its neighbours, and
/// the swing fades in and out so the wave starts and ends on the rest pose.
List<double> _barHalfLengthsAt(double progress) {
  final wave = _waveTiming.transform(progress);
  final envelope = math.sin(math.pi * wave);
  return [
    for (var index = 0; index < _barMaxHalfLengths.length; index++)
      _barHalfLength(
        index,
        envelope *
            math.sin(2 * math.pi * _waveCycles * wave - index * _barPhaseStep),
      ),
  ];
}

/// [swing] runs from -1 (shortest) through 0 (rest) to 1 (longest).
double _barHalfLength(int index, double swing) {
  final rest = LogoPose.rest.barHalfLengths[index];
  if (swing >= 0) return rest + (_barMaxHalfLengths[index] - rest) * swing;
  return rest + (rest - _barMinHalfLength) * swing;
}

WordmarkFrame _wordmarkAt(double progress) {
  final shown = _wordmarkTiming.transform(progress);
  return WordmarkFrame(opacity: shown, lift: _wordmarkTravel * (1 - shown));
}
