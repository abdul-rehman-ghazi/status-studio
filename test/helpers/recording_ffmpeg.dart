import 'dart:io';

import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';

/// Records each run and writes an empty output file, or throws [failure]
/// from every run when it is set.
class RecordingFfmpegRunner implements FfmpegRunner {
  RecordingFfmpegRunner({this.failure});

  final Exception? failure;
  final runs = <List<String>>[];

  @override
  Future<void> run(
    List<String> arguments, {
    void Function(Duration processed)? onTime,
  }) async {
    runs.add(arguments);
    if (failure case final failure?) {
      throw failure;
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
