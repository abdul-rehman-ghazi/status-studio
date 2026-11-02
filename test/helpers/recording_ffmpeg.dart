import 'dart:io';

import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';

/// Records each run and writes an empty output file, or fails every run
/// when [failing].
class RecordingFfmpegRunner implements FfmpegRunner {
  RecordingFfmpegRunner({this.failing = false});

  final bool failing;
  final runs = <List<String>>[];

  @override
  Future<void> run(
    List<String> arguments, {
    void Function(Duration processed)? onTime,
  }) async {
    runs.add(arguments);
    if (failing) {
      throw const FfmpegFailedException('no decoder');
    }
    await File(arguments.last).writeAsBytes(const []);
  }

  @override
  Future<void> cancel() async {}
}

/// Succeeds at every run without writing anything, for widget tests whose
/// renders produce no real files.
class SilentFfmpegRunner implements FfmpegRunner {
  const SilentFfmpegRunner();

  @override
  Future<void> run(
    List<String> arguments, {
    void Function(Duration processed)? onTime,
  }) async {}

  @override
  Future<void> cancel() async {}
}
