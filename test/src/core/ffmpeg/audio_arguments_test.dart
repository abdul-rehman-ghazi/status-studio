import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';

void main() {
  test('wav_arguments_make_16khz_mono_pcm', () {
    final arguments = wavArguments(inputPath: 'a.m4a', outputPath: 'a.wav');

    expect(arguments, [
      '-y',
      '-i',
      'a.m4a',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      'a.wav',
    ]);
  });

  test('chunk_arguments_use_segment_muxer', () {
    final arguments = chunkArguments(
      wavPath: 'a.wav',
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
