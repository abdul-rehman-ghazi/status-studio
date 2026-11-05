import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';

const _sampleRate = 16000;
const _bytesPerSample = 2;

/// Beyond this many times the usual window, a source is the whole-video
/// fallback (FR-15) and the waveform shows only the stretch around the clip.
/// A video this long or shorter gets one waveform for all of it, so a nudge
/// never needs another.
const _longestWholeVideoShown = Duration(minutes: 10);

/// A longer video shows only this much from the clip's start: its WAV is
/// about 1.9 MB a minute and is read into memory.
const _longestShownAroundClip = Duration(minutes: 5);

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

/// The stretch of video the waveform covers: all of the video when it is
/// short, otherwise a few minutes from the clip's start, so the WAV never
/// becomes a long soundtrack.
ClipWindow waveformWindowFor(
  ClipSource source,
  ClipRange clip,
  Duration videoDuration,
) {
  final whole = source.window;
  if (whole.end - whole.start <= _longestWholeVideoShown) {
    return whole;
  }
  final aroundClip = clipWindowFor(clip, videoDuration);
  final cappedEnd = aroundClip.start + _longestShownAroundClip;
  return ClipWindow(
    start: aroundClip.start,
    end: aroundClip.end < cappedEnd ? aroundClip.end : cappedEnd,
  );
}

/// The loudest sample in each of [buckets] equal slices of the request's
/// window, scaled so the loudest slice is 1. Silence gives all zeros.
///
/// Expects 16 kHz mono 16-bit PCM, as made by `excerptWavArguments`.
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
  _Pcm samples,
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

/// Little-endian 16-bit samples read in place, without copying the audio.
class _Pcm {
  _Pcm(this._view, this._start, int end)
    : length = (end - _start) ~/ _bytesPerSample;

  final ByteData _view;
  final int _start;
  final int length;

  int operator [](int index) =>
      _view.getInt16(_start + index * _bytesPerSample, Endian.little);
}

/// The `data` chunk's samples. Chunks are walked rather than assuming a
/// 44-byte header: FFmpeg adds a `LIST` chunk before `data`.
_Pcm _pcmSamples(Uint8List wavBytes) {
  final view = ByteData.sublistView(wavBytes);
  var chunkStart = 12;
  while (chunkStart + 8 <= wavBytes.length) {
    final id = String.fromCharCodes(wavBytes, chunkStart, chunkStart + 4);
    final size = view.getUint32(chunkStart + 4, Endian.little);
    final body = chunkStart + 8;
    if (id == 'data') {
      return _Pcm(view, body, math.min(body + size, wavBytes.length));
    }
    chunkStart = body + size + size % 2;
  }
  throw const FormatException('The WAV has no data chunk.');
}
