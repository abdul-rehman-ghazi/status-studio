import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// How far one video's source preparation has got, from 0 to 1.
final sourceVideoProgressProvider =
    NotifierProvider.family<SourceVideoProgress, double, String>(
      SourceVideoProgress.new,
    );

class SourceVideoProgress extends Notifier<double> {
  SourceVideoProgress(this.videoId);

  final String videoId;

  @override
  double build() => 0;

  void report(double fraction) => state = fraction;
}

/// The muxed source video for preview and rendering, per video ID, so one
/// reel can never show another reel's file or progress. `null` until
/// [SourceVideoController.prepare] is first called.
final sourceVideoProvider =
    AsyncNotifierProvider.family<SourceVideoController, File?, String>(
      SourceVideoController.new,
    );

class SourceVideoController extends AsyncNotifier<File?> {
  SourceVideoController(this.videoId);

  final String videoId;
  Future<void>? _running;

  @override
  Future<File?> build() async => null;

  /// Downloads and muxes [video] in the background. Calls while it runs
  /// share that run; calls after it succeeded do nothing; calls after it
  /// failed retry.
  Future<void> prepare(SourceVideo video) {
    if (video.videoId != videoId) {
      throw ArgumentError.value(video.videoId, 'video', 'is not $videoId');
    }
    if (state.hasValue && state.value != null) {
      return Future.value();
    }
    return _running ??= _download(video).whenComplete(() {
      _running = null;
    });
  }

  Future<void> _download(SourceVideo video) async {
    state = const AsyncLoading();
    final progress = ref.read(sourceVideoProgressProvider(videoId).notifier)
      ..report(0);
    final result = await AsyncValue.guard<File?>(
      () => ref
          .read(videoSourceProvider)
          .prepareSourceVideo(video, onProgress: progress.report),
    );
    if (ref.mounted) {
      state = result;
    }
  }
}
