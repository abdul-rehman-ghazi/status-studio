import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/local_video_facts.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// Reads facts about local media files with FFprobe.
class MediaProbe {
  const MediaProbe();

  /// Reads a local video the user brought in (spec FR-1). Throws
  /// [VideoUnreadableException] when it can't be read, has no video, or has
  /// no audio track: the §8 "Can't read this video" cases.
  Future<LocalVideoFacts> readLocalVideo(String path) async {
    final facts = await _readVideoFacts(path);
    return facts.requireAudio();
  }

  Future<LocalVideoFacts> _readVideoFacts(String path) async {
    final session = await FFprobeKit.executeWithArguments(
      localVideoProbeArguments(path),
    );
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw const VideoUnreadableException('ffprobe could not read the file');
    }
    final output = await session.getOutput() ?? '';
    return parseLocalVideoFacts(output);
  }

  /// The first video stream's frame size as a player shows it: width and
  /// height swap when the file is stored turned by 90 or 270 degrees, since
  /// Media3 and FFmpeg both turn frames before crops apply. Throws
  /// [VideoUnreadableException] when the file can't be read or has no video.
  Future<OutputSize> videoSize(String path) async {
    final facts = await _readVideoFacts(path);
    return OutputSize(facts.displayedWidth, facts.displayedHeight);
  }
}

final mediaProbeProvider = Provider<MediaProbe>((ref) => const MediaProbe());
