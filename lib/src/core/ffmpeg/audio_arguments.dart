/// Converts any audio to what whisper.cpp reads: 16 kHz mono 16-bit PCM.
List<String> wavArguments({
  required String inputPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-i',
    inputPath,
    '-ac',
    '1',
    '-ar',
    '16000',
    '-c:a',
    'pcm_s16le',
    outputPath,
  ];
}

/// Cuts a WAV into back-to-back pieces of [chunkSeconds] without
/// re-encoding.
List<String> chunkArguments({
  required String wavPath,
  required String outputPattern,
  required int chunkSeconds,
}) {
  return [
    '-y',
    '-i',
    wavPath,
    '-f',
    'segment',
    '-segment_time',
    '$chunkSeconds',
    '-c',
    'copy',
    outputPattern,
  ];
}
