import 'dart:async';
import 'dart:io';

import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/data/clip_source_preparer.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';

/// Prepares instantly: a clip file whose time zero is the window's start.
/// Counts calls; fails while [failing]; never finishes while [stalled].
class FakeClipSourcePreparer extends ClipSourcePreparer {
  FakeClipSourcePreparer({this.failing = false, this.stalled = false})
    : super(
        videos: const FakeVideoSource(),
        downloader: RangedDownloader(HttpClient()),
        ffmpeg: const FfmpegRunner(),
      );

  bool failing;
  final bool stalled;
  var calls = 0;

  /// When set, each preparation waits for it before finishing.
  Completer<void>? gate;

  @override
  Future<ClipSource> prepare(
    ClipPrepareRequest request, {
    required void Function(double fraction) onProgress,
  }) async {
    calls++;
    onProgress(0.4);
    if (stalled) {
      return Completer<ClipSource>().future;
    }
    await gate?.future;
    if (failing) {
      throw const FileSystemException('disk error');
    }
    final window = clipWindowFor(request.clip, request.video.duration);
    onProgress(1);
    return ClipSource(
      file: File('${request.video.videoId}-clip.mp4'),
      offset: window.start,
      window: window,
    );
  }
}
