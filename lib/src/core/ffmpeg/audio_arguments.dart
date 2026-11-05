import 'package:flutter/foundation.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_time.dart';

/// Where the pieces and their segment list go.
@immutable
class ScriptPieces {
  const ScriptPieces({
    required this.inputPath,
    required this.folderPath,
    required this.chunkSeconds,
  });

  final String inputPath;
  final String folderPath;
  final int chunkSeconds;

  /// FFmpeg lists each finished piece here as `name,start,end` (CSV).
  String get segmentListPath => '$folderPath/$segmentListName';
}

const segmentListName = 'pieces.csv';

/// The video's first audio stream as 16 kHz mono FLAC pieces of about
/// [ScriptPieces.chunkSeconds] each, the small files Groq is sent (spec
/// FR-3, FR-12a). The video stream is dropped.
///
/// Cuts fall on audio frames, so a piece starts a fraction of a second
/// after a multiple of the length; the segment list has the exact times.
List<String> scriptPiecesArguments(ScriptPieces pieces) {
  return [
    '-y',
    '-i',
    pieces.inputPath,
    '-vn',
    '-map',
    '0:a:0',
    '-ac',
    '1',
    '-ar',
    '16000',
    '-c:a',
    'flac',
    '-f',
    'segment',
    '-segment_time',
    '${pieces.chunkSeconds}',
    '-reset_timestamps',
    '1',
    '-segment_list',
    pieces.segmentListPath,
    '-segment_list_type',
    'csv',
    '${pieces.folderPath}/chunk_%03d.flac',
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
