import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/export/domain/sound_boost.dart';

/// Measures a clip's loudness with FFmpeg's `loudnorm` (spec FR-42).
class LoudnessMeter {
  const LoudnessMeter(this.ffmpeg);

  final FfmpegRunner ffmpeg;

  /// [range] is in the file's own time. Throws [LoudnessUnreadableException]
  /// when the file has no sound track or FFmpeg fails.
  Future<Loudness> measure(String path, ClipRange range) async {
    final String log;
    try {
      log = await ffmpeg.runForLog(_arguments(path, range));
    } on FfmpegFailedException catch (error) {
      throw LoudnessUnreadableException(error.log);
    }
    return loudnessFromLog(log);
  }

  List<String> _arguments(String path, ClipRange range) => [
    '-hide_banner',
    '-nostats',
    '-ss',
    _seconds(range.start),
    '-t',
    _seconds(range.end - range.start),
    '-i',
    path,
    '-vn',
    '-sn',
    '-dn',
    '-af',
    'loudnorm=print_format=json',
    '-f',
    'null',
    '-',
  ];

  String _seconds(Duration time) =>
      (time.inMilliseconds / 1000).toStringAsFixed(3);
}

final loudnessMeterProvider = Provider<LoudnessMeter>(
  (ref) => LoudnessMeter(ref.watch(ffmpegRunnerProvider)),
);
