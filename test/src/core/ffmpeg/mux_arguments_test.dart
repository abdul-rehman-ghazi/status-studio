import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/mux_arguments.dart';

void main() {
  test('mux_copies_streams_without_reencoding', () {
    final arguments = muxArguments(
      videoPath: 'v.mp4',
      audioPath: 'a.m4a',
      outputPath: 'out.mp4',
    );

    expect(arguments, [
      '-y',
      '-i',
      'v.mp4',
      '-i',
      'a.m4a',
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      'out.mp4',
    ]);
  });

  test('clip_mux_delays_each_input_by_its_start', () {
    final arguments = clipMuxArguments(
      video: const MuxInput(path: 'v.mp4', delay: Duration(seconds: 5)),
      audio: const MuxInput(path: 'a.mp4', delay: Duration.zero),
      outputPath: 'out.mp4',
    );

    expect(arguments, [
      '-y',
      '-itsoffset',
      '5.000',
      '-i',
      'v.mp4',
      '-itsoffset',
      '0.000',
      '-i',
      'a.mp4',
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      'out.mp4',
    ]);
  });
}
