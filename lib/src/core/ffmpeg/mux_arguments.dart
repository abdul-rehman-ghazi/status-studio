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
