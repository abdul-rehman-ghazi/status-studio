import 'dart:io';

import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// Counts source preparations; fails them while [failing] is set.
class CountingVideoSource extends FakeVideoSource {
  CountingVideoSource({this.failing = false});

  bool failing;
  var prepareCount = 0;

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    prepareCount++;
    if (failing) {
      throw const FileSystemException('disk error');
    }
    onProgress(0.5);
    return super.prepareSourceVideo(video, onProgress: onProgress);
  }
}
