import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:status_studio/src/features/source/data/video_picker.dart';

void main() {
  test('closing_the_picker_is_a_cancel', () {
    final result = videoPickResultOf(null);

    expect(result, isA<VideoPickCancelled>());
  });

  test('choosing_a_video_gives_its_path_and_name', () {
    final result = videoPickResultOf(
      XFile('/cache/picked/clip.mp4', name: 'clip.mp4'),
    );

    expect(
      result,
      const VideoPicked(
        path: '/cache/picked/clip.mp4',
        displayName: 'clip.mp4',
      ),
    );
  });
}
