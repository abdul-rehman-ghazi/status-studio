import 'package:flutter/foundation.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_time.dart';

/// Converts any audio to what whisper.cpp reads: 16 kHz mono 16-bit PCM.
List<String> wavArguments({
  required String inputPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-i',
    inputPath,
    '-ac',
    '1',
    '-ar',
    '16000',
    '-c:a',
    'pcm_s16le',
    outputPath,
  ];
}

/// Cuts a WAV into back-to-back pieces of [chunkSeconds] without
/// re-encoding.
List<String> chunkArguments({
  required String wavPath,
  required String outputPattern,
  required int chunkSeconds,
}) {
  return [
    '-y',
    '-i',
    wavPath,
    '-f',
    'segment',
    '-segment_time',
    '$chunkSeconds',
    '-c',
    'copy',
    outputPattern,
  ];
}

/// A stretch of a media file's audio, in that file's own time.
@immutable
class WavExcerpt {
  const WavExcerpt({
    required this.inputPath,
    required this.outputPath,
    required this.start,
    required this.end,
  });

  final String inputPath;
  final String outputPath;
  final Duration start;
  final Duration end;
}

/// The excerpt as a 16 kHz mono WAV whose time zero is the excerpt's start.
///
/// A clip file's audio can start late (it's muxed with `-itsoffset`); the
/// resample filter fills that gap with silence instead of dropping it, so
/// sounds stay where they are in the video.
List<String> excerptWavArguments(WavExcerpt excerpt) {
  return [
    '-y',
    '-ss',
    ffmpegSeconds(excerpt.start),
    '-to',
    ffmpegSeconds(excerpt.end),
    '-i',
    excerpt.inputPath,
    '-vn',
    '-af',
    'aresample=async=1:first_pts=0',
    '-ac',
    '1',
    '-ar',
    '16000',
    '-c:a',
    'pcm_s16le',
    excerpt.outputPath,
  ];
}
