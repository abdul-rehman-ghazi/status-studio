import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// Reads facts about local media files with FFprobe.
class MediaProbe {
  const MediaProbe();

  /// The first video stream's frame size. Throws [FfmpegFailedException]
  /// when the file can't be read or has no video.
  Future<OutputSize> videoSize(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final streams = session.getMediaInformation()?.getStreams() ?? const [];
    for (final stream in streams) {
      final width = stream.getWidth();
      final height = stream.getHeight();
      if (stream.getType() == 'video' && width != null && height != null) {
        return OutputSize(width, height);
      }
    }
    final log = await session.getAllLogsAsString() ?? '';
    throw FfmpegFailedException('No video stream in $path. $log');
  }
}

final mediaProbeProvider = Provider<MediaProbe>((ref) => const MediaProbe());
