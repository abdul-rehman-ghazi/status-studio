import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/core/time_format.dart';

const _bytesPerMegabyte = 1000000;
const _bytesPerKilobyte = 1000;

/// Below this many megabytes, sizes keep one decimal.
const _wholeMegabytesFrom = 10;

enum WorkUnit { bytes, audioMilliseconds }

/// How much of one step is done: bytes downloaded, or audio transcribed.
@immutable
class WorkAmount {
  const WorkAmount({
    required this.done,
    required this.total,
    required this.unit,
  });

  final int done;

  /// 0 when the total isn't known.
  final int total;
  final WorkUnit unit;

  double get fraction => total <= 0 ? 0 : math.min(1, done / total);

  @override
  bool operator ==(Object other) =>
      other is WorkAmount &&
      other.done == done &&
      other.total == total &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(done, total, unit);
}

/// A step's average speed since its first sample in this run, so work
/// finished in an earlier run (a cached file, resumed chunks) doesn't
/// count.
@immutable
class WorkRate {
  const WorkRate.from(this.first, this.firstAt);

  final WorkAmount first;

  /// When [first] arrived, measured from any fixed starting point.
  final Duration firstAt;

  /// Units per second, or null until some time has passed.
  double? perSecond(WorkAmount latest, Duration at) {
    final elapsed = at - firstAt;
    if (elapsed <= Duration.zero) {
      return null;
    }
    return (latest.done - first.done) /
        (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
  }
}

/// `45 % · 220 of 487 MB · 3.2 MB/s`, or `33 % · 3:00 of 9:08 · 1.3× real
/// time`; the speed is left out until it is known.
String workLine(WorkAmount amount, {double? perSecond}) {
  final percent = '${(amount.fraction * 100).round()} %';
  final parts = [
    percent,
    _doneOfTotal(amount),
    if (perSecond != null) _speed(amount.unit, perSecond),
  ];
  return parts.join(' · ');
}

String _doneOfTotal(WorkAmount amount) => switch (amount.unit) {
  WorkUnit.bytes => _megabytesOfTotal(amount),
  WorkUnit.audioMilliseconds =>
    '${formatTimestamp(Duration(milliseconds: amount.done))} of '
        '${formatTimestamp(Duration(milliseconds: amount.total))}',
};

String _megabytesOfTotal(WorkAmount amount) {
  final decimals = amount.total < _wholeMegabytesFrom * _bytesPerMegabyte
      ? 1
      : 0;
  String megabytes(int bytes) =>
      (bytes / _bytesPerMegabyte).toStringAsFixed(decimals);
  return '${megabytes(amount.done)} of ${megabytes(amount.total)} MB';
}

String _speed(WorkUnit unit, double perSecond) => switch (unit) {
  WorkUnit.bytes when perSecond < _bytesPerMegabyte =>
    '${(perSecond / _bytesPerKilobyte).round()} KB/s',
  WorkUnit.bytes =>
    '${(perSecond / _bytesPerMegabyte).toStringAsFixed(1)} MB/s',
  WorkUnit.audioMilliseconds =>
    '${(perSecond / Duration.millisecondsPerSecond).toStringAsFixed(1)}× '
        'real time',
};
