import 'package:status_studio/src/core/ffmpeg/ffmpeg_time.dart';

/// Joins a video-only and an audio-only file without re-encoding, with the
/// index at the front so the preview can start before the whole file loads.
List<String> muxArguments({
  required String videoPath,
  required String audioPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-i',
    videoPath,
    '-i',
    audioPath,
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c',
    'copy',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}

/// One input of a clip mux and how late it starts after the clip file's
/// time zero.
class MuxInput {
  const MuxInput({required this.path, required this.delay});

  final String path;
  final Duration delay;
}

/// Muxes a clip window's video and audio without re-encoding. FFmpeg moves
/// each input to start at 0, so each one is delayed by how much later its
/// first segment starts than the clip's time zero; otherwise the two
/// streams would drift apart by the difference.
List<String> clipMuxArguments({
  required MuxInput video,
  required MuxInput audio,
  required String outputPath,
}) {
  return [
    '-y',
    '-itsoffset',
    ffmpegSeconds(video.delay),
    '-i',
    video.path,
    '-itsoffset',
    ffmpegSeconds(audio.delay),
    '-i',
    audio.path,
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c',
    'copy',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}
