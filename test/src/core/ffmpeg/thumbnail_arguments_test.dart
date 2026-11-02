import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/thumbnail_arguments.dart';

void main() {
  test('thumbnail_takes_first_frame_at_270_wide', () {
    final arguments = thumbnailArguments(
      videoPath: 'reel.mp4',
      outputPath: 'reel.jpg',
    );

    expect(arguments, [
      '-y',
      '-ss',
      '0',
      '-i',
      'reel.mp4',
      '-frames:v',
      '1',
      '-vf',
      'scale=270:-2',
      'reel.jpg',
    ]);
  });
}
