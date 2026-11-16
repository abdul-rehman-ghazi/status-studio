import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// A kept video as its own cut (spec FR-51): the file covers the whole
/// video, time zero at 0, so nothing is downloaded or cut. Throws
/// [KeptVideoMissingException] when the file is gone.
CutFile keptVideoCut(SourceCache sources, SourceVideo video) {
  final kept = sources.keptLocalVideos(video.videoId);
  if (kept.isEmpty) {
    throw KeptVideoMissingException(video.videoId);
  }
  return CutFile(
    file: kept.first,
    streamsKey: keptVideoStreamsKey,
    fileStart: Duration.zero,
    covered: ClipWindow(start: Duration.zero, end: video.duration),
  );
}
