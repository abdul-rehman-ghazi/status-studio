import 'dart:math' as math;

/// Common for phone video: loud enough over a phone speaker, with room left
/// for the limiter (spec FR-42).
const _targetLufs = -14.0;

/// More than this raises the noise floor into audible hiss.
const _largestBoostDb = 15.0;
const _smallestBoostDb = 0.5;

/// `loudnorm` reports silence as -70 LUFS or `-inf`.
const _silenceLufs = -70.0;

/// A clip's integrated loudness, in LUFS.
class Loudness {
  const Loudness(this.lufs);

  final double lufs;
}

/// FFmpeg couldn't measure the clip: no sound track, or the run failed.
class LoudnessUnreadableException implements Exception {
  const LoudnessUnreadableException(this.reason);

  final String reason;

  @override
  String toString() => 'LoudnessUnreadableException: $reason';
}

final _inputLoudness = RegExp(r'"input_i"\s*:\s*"([^"]+)"');

/// Reads `input_i` from the JSON that `loudnorm=print_format=json` writes
/// to FFmpeg's log. Throws [LoudnessUnreadableException] when it is missing.
Loudness loudnessFromLog(String log) {
  final match = _inputLoudness.firstMatch(log);
  if (match == null) {
    throw const LoudnessUnreadableException('No loudness in the log.');
  }
  final value = match.group(1)!;
  if (value.contains('inf')) {
    return const Loudness(double.negativeInfinity);
  }
  final lufs = double.tryParse(value);
  if (lufs == null) {
    throw LoudnessUnreadableException('Loudness "$value" is not a number.');
  }
  return Loudness(lufs);
}

/// The linear gain that raises [loudness] towards the target (spec FR-42).
/// It is 1, no change, for a clip that is loud enough or silent.
double soundGainFor(Loudness loudness) {
  if (loudness.lufs <= _silenceLufs) {
    return 1;
  }
  final boostDb = (_targetLufs - loudness.lufs).clamp(0.0, _largestBoostDb);
  if (boostDb < _smallestBoostDb) {
    return 1;
  }
  return math.pow(10, boostDb / 20).toDouble();
}
