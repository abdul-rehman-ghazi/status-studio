import 'package:flutter/foundation.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_time.dart';

const _defaultFramesPerSecond = 4.0;
const _slowestFramesPerSecond = 2.0;
const _mostFrames = 240;

/// How many frames of a clip to look at per second (spec FR-23): four, or
/// fewer for a long clip so there are at most 240 frames, but never fewer
/// than two a second.
double samplingRateFor(Duration clipLength) {
  final seconds = clipLength.inMicroseconds / Duration.microsecondsPerSecond;
  final capped = _mostFrames / seconds;
  if (capped >= _defaultFramesPerSecond) {
    return _defaultFramesPerSecond;
  }
  return capped < _slowestFramesPerSecond ? _slowestFramesPerSecond : capped;
}

/// The video time of frame [index] of a run sampled from the clip's start.
Duration frameTime({
  required Duration clipStart,
  required int index,
  required double framesPerSecond,
}) {
  final microseconds = index * Duration.microsecondsPerSecond / framesPerSecond;
  return clipStart + Duration(microseconds: microseconds.round());
}

/// Small frames of one stretch of a clip file, in that file's own time.
@immutable
class FrameSampling {
  const FrameSampling({
    required this.inputPath,
    required this.outputDirectory,
    required this.cutsPath,
    required this.start,
    required this.end,
    required this.framesPerSecond,
  });

  final String inputPath;
  final String outputDirectory;

  /// Where FFmpeg writes the times of scene cuts, one per line.
  final String cutsPath;
  final Duration start;
  final Duration end;
  final double framesPerSecond;
}

/// Samples frames as numbered JPEGs (`frame0000.jpg`, …) and lists scene
/// cuts, in one pass over the clip file (spec FR-23). The JPEG encoder is the
/// one the bundled build has; it has no PNG encoder. The scene detector looks
/// at every frame, and only then are frames dropped to the sampling rate.
List<String> sampledFramesArguments(FrameSampling sampling) {
  final filters = [
    'scale=640:640:force_original_aspect_ratio=decrease',
    'scdet=threshold=10',
    'metadata=mode=print:key=lavfi.scd.time:file='
        '${_escapedFilterValue(sampling.cutsPath)}',
    'fps=${_plainNumber(sampling.framesPerSecond)}',
  ].join(',');
  return [
    '-y',
    '-ss',
    ffmpegSeconds(sampling.start),
    '-to',
    ffmpegSeconds(sampling.end),
    '-i',
    sampling.inputPath,
    '-an',
    '-sn',
    '-vf',
    filters,
    '-fps_mode',
    'passthrough',
    '-q:v',
    '5',
    '-start_number',
    '0',
    '${sampling.outputDirectory}/frame%04d.jpg',
  ];
}

/// The cut times FFmpeg's metadata filter printed (`lavfi.scd.time=3.086`).
List<Duration> parseSceneCuts(String text) {
  final cuts = <Duration>[];
  for (final line in text.split('\n')) {
    final match = RegExp(r'lavfi\.scd\.time=([0-9.]+)').firstMatch(line);
    if (match == null) {
      continue;
    }
    final seconds = double.tryParse(match.group(1)!);
    if (seconds != null) {
      cuts.add(
        Duration(
          microseconds: (seconds * Duration.microsecondsPerSecond).round(),
        ),
      );
    }
  }
  return cuts;
}

/// A value inside a filter chain: backslashes and colons need escaping.
String _escapedFilterValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll(':', r'\:');

String _plainNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
