import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';

const _sampleRate = 16000;
const _bytesPerSample = 2;

/// Which WAV to draw and where it sits in video time.
@immutable
class WaveformRequest {
  const WaveformRequest({
    required this.wavPath,
    required this.offset,
    required this.window,
  });

  final String wavPath;

  /// The video time at which the WAV's own time zero falls.
  final Duration offset;
  final ClipWindow window;

  @override
  bool operator ==(Object other) =>
      other is WaveformRequest &&
      other.wavPath == wavPath &&
      other.offset == offset &&
      other.window == window;

  @override
  int get hashCode => Object.hash(wavPath, offset, window);
}

/// The loudest sample in each of [buckets] equal slices of the request's
/// window, scaled so the loudest slice is 1. Silence gives all zeros.
///
/// Expects 16 kHz mono 16-bit PCM, as made by `wavArguments`.
List<double> waveformPeaks(
  Uint8List wavBytes,
  WaveformRequest request, {
  required int buckets,
}) {
  final samples = _pcmSamples(wavBytes);
  final loudest = _loudestPerBucket(samples, request, buckets);
  final overall = loudest.fold(0, math.max);
  if (overall == 0) {
    return List.filled(buckets, 0);
  }
  return [for (final peak in loudest) peak / overall];
}

List<int> _loudestPerBucket(
  Int16List samples,
  WaveformRequest request,
  int buckets,
) {
  final loudest = List.filled(buckets, 0);
  final windowStart = _toSamples(request.window.start - request.offset);
  final windowLength = _toSamples(request.window.end - request.window.start);
  if (windowLength <= 0) {
    return loudest;
  }
  final first = math.max(0, windowStart.ceil());
  final last = math.min(samples.length, (windowStart + windowLength).ceil());
  for (var index = first; index < last; index++) {
    final bucket = ((index - windowStart) / windowLength * buckets).floor();
    if (bucket < buckets) {
      loudest[bucket] = math.max(loudest[bucket], samples[index].abs());
    }
  }
  return loudest;
}

double _toSamples(Duration time) =>
    time.inMicroseconds * _sampleRate / Duration.microsecondsPerSecond;

/// The `data` chunk's samples. Chunks are walked rather than assuming a
/// 44-byte header: FFmpeg adds a `LIST` chunk before `data`.
Int16List _pcmSamples(Uint8List wavBytes) {
  final view = ByteData.sublistView(wavBytes);
  var chunkStart = 12;
  while (chunkStart + 8 <= wavBytes.length) {
    final id = String.fromCharCodes(wavBytes, chunkStart, chunkStart + 4);
    final size = view.getUint32(chunkStart + 4, Endian.little);
    final body = chunkStart + 8;
    if (id == 'data') {
      final end = math.min(body + size, wavBytes.length);
      return _littleEndianSamples(view, body, end);
    }
    chunkStart = body + size + size % 2;
  }
  throw const FormatException('The WAV has no data chunk.');
}

Int16List _littleEndianSamples(ByteData view, int start, int end) {
  final count = (end - start) ~/ _bytesPerSample;
  return Int16List.fromList([
    for (var index = 0; index < count; index++)
      view.getInt16(start + index * _bytesPerSample, Endian.little),
  ]);
}
