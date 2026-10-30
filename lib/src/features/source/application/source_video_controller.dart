import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// How far the source video preparation has got, from 0 to 1.
final sourceVideoProgressProvider =
    NotifierProvider<SourceVideoProgress, double>(SourceVideoProgress.new);

class SourceVideoProgress extends Notifier<double> {
  @override
  double build() => 0;

  void report(double fraction) => state = fraction;
}

/// The muxed source video for preview and rendering; `null` until
/// [SourceVideoController.prepare] is first called.
final sourceVideoProvider = AsyncNotifierProvider<SourceVideoController, File?>(
  SourceVideoController.new,
);

class SourceVideoController extends AsyncNotifier<File?> {
  String? _videoId;

  @override
  Future<File?> build() async => null;

  /// Downloads and muxes [video] in the background. Calls for the video
  /// already being prepared, or already ready, do nothing.
  Future<void> prepare(SourceVideo video) async {
    if (video.videoId == _videoId && !state.hasError) {
      return;
    }
    _videoId = video.videoId;
    state = const AsyncLoading();
    final progress = ref.read(sourceVideoProgressProvider.notifier)..report(0);
    final result = await AsyncValue.guard<File?>(
      () => ref
          .read(videoSourceProvider)
          .prepareSourceVideo(video, onProgress: progress.report),
    );
    // A newer video may have been asked for while this one downloaded.
    if (!ref.mounted || video.videoId != _videoId) {
      return;
    }
    state = result;
  }
}
