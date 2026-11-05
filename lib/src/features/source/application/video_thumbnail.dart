import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/thumbnail_arguments.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// The picture for the Source card: the first frame of the kept video,
/// cut once and reused.
///
/// Throws [VideoUnreadableException] when nothing is kept under the ID; the
/// card then shows its icon instead.
final videoThumbnailProvider = FutureProvider.family<File, String>((
  ref,
  videoId,
) async {
  final cache = await ref.watch(sourceCacheProvider.future);
  final thumbnail = cache.thumbnailFile(videoId);
  if (thumbnail.existsSync()) {
    return thumbnail;
  }
  final kept = cache.keptLocalVideos(videoId);
  if (kept.isEmpty) {
    throw VideoUnreadableException('no kept video for $videoId');
  }
  await ref
      .watch(ffmpegRunnerProvider)
      .run(
        thumbnailArguments(
          videoPath: kept.first.path,
          outputPath: thumbnail.path,
        ),
      );
  return thumbnail;
});
