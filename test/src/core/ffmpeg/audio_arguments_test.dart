import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';

void main() {
  test('excerpt_wav_pads_a_late_audio_start', () {
    final arguments = excerptWavArguments(
      const WavExcerpt(
        inputPath: 'clip.mp4',
        outputPath: 'wave.wav',
        start: Duration(seconds: 3),
        end: Duration(milliseconds: 53500),
      ),
    );

    expect(arguments, [
      '-y',
      '-ss',
      '3.000',
      '-to',
      '53.500',
      '-i',
      'clip.mp4',
      '-vn',
      '-af',
      'aresample=async=1:first_pts=0',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      'wave.wav',
    ]);
  });

  test('chunk_arguments_use_segment_muxer', () {
    final arguments = chunkArguments(
      inputPath: 'a.wav',
      outputPattern: 'chunk_%03d.wav',
      chunkSeconds: 90,
    );

    expect(arguments, [
      '-y',
      '-i',
      'a.wav',
      '-f',
      'segment',
      '-segment_time',
      '90',
      '-c',
      'copy',
      'chunk_%03d.wav',
    ]);
  });
}
