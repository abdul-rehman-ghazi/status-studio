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
}
