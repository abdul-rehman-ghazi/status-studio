import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/frame_arguments.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';

/// Small frames sampled from a clip, with where its scene cuts are (spec
/// FR-23). They live in [directory] until [delete].
class SampledFrames {
  const SampledFrames({
    required this.directory,
    required this.frames,
    required this.framesPerSecond,
    required this.sceneCuts,
  });

  final Directory directory;

  /// In time order; frame k is at `clip.start + k / framesPerSecond`.
  final List<File> frames;
  final double framesPerSecond;

  /// In video time. None when FFmpeg left no cut file, which is different
  /// from an empty list (it looked and found none).
  final List<Duration>? sceneCuts;

  Future<void> delete() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

abstract interface class FrameExtractor {
  /// Samples frames of [clip] from the downloaded [source], with no new
  /// download. Throws [FollowFailedException] when FFmpeg fails or makes
  /// nothing; the frames are deleted then.
  Future<SampledFrames> extract(
    ClipSource source,
    ClipRange clip,
    FfmpegCancelHandle cancel,
  );
}

class FfmpegFrameExtractor implements FrameExtractor {
  FfmpegFrameExtractor({
    required this.runner,
    Directory Function()? makeDirectory,
  }) : _makeDirectory =
           makeDirectory ??
           (() => Directory.systemTemp.createTempSync('follow_frames'));

  final CancellableFfmpegRunner runner;
  final Directory Function() _makeDirectory;

  @override
  Future<SampledFrames> extract(
    ClipSource source,
    ClipRange clip,
    FfmpegCancelHandle cancel,
  ) async {
    final directory = _makeDirectory();
    final rate = samplingRateFor(clip.length);
    try {
      try {
        await _sample(source, clip, directory, rate, cancel, findCuts: true);
      } on FfmpegFailedException {
        if (cancel.isCancelled) {
          rethrow;
        }
        // A build without the scene filter fails the whole run; the frames
        // matter more, and a face that jumps stands in for a cut.
        await _emptied(directory);
        await _sample(source, clip, directory, rate, cancel, findCuts: false);
      }
      return await _read(directory, rate, clip.start);
    } on FfmpegFailedException catch (failure) {
      await _deleted(directory);
      throw FollowFailedException(failure.log);
    } on Object {
      await _deleted(directory);
      rethrow;
    }
  }

  Future<void> _sample(
    ClipSource source,
    ClipRange clip,
    Directory directory,
    double rate,
    FfmpegCancelHandle cancel, {
    required bool findCuts,
  }) {
    final sampling = FrameSampling(
      inputPath: source.file.path,
      outputDirectory: directory.path,
      cutsPath: findCuts ? '${directory.path}/cuts.txt' : null,
      // The clip file's own time zero is `offset` into the video.
      start: clip.start - source.offset,
      end: clip.end - source.offset,
      framesPerSecond: rate,
    );
    return runner.run(sampledFramesArguments(sampling), cancel);
  }

  Future<void> _emptied(Directory directory) async {
    await for (final entry in directory.list()) {
      await entry.delete(recursive: true);
    }
  }

  Future<void> _deleted(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<SampledFrames> _read(
    Directory directory,
    double rate,
    Duration clipStart,
  ) async {
    final frames =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => RegExp(r'frame\d+\.jpg$').hasMatch(file.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (frames.isEmpty) {
      throw const FollowFailedException('FFmpeg made no frames.');
    }
    final cutsFile = File('${directory.path}/cuts.txt');
    final cuts = await cutsFile.exists()
        ? [
            for (final cut in parseSceneCuts(await cutsFile.readAsString()))
              clipStart + cut,
          ]
        : null;
    return SampledFrames(
      directory: directory,
      frames: frames,
      framesPerSecond: rate,
      sceneCuts: cuts,
    );
  }
}

final frameExtractorProvider = Provider<FrameExtractor>(
  (ref) =>
      FfmpegFrameExtractor(runner: ref.watch(cancellableFfmpegRunnerProvider)),
);
