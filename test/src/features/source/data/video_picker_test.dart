import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:status_studio/src/features/source/data/video_picker.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

import '../../../../helpers/fake_video_picker.dart';

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

  test('an_empty_lost_data_response_is_no_lost_video', () {
    final result = lostVideoResultOf(LostDataResponse.empty());

    expect(result, isA<NoLostVideo>());
  });

  test('a_lost_video_gives_its_path_and_name', () {
    final result = lostVideoResultOf(
      LostDataResponse(
        type: RetrieveType.video,
        files: [XFile('/cache/picked/clip.mp4', name: 'clip.mp4')],
      ),
    );

    expect(
      (result as LostVideoFound).video,
      const VideoPicked(
        path: '/cache/picked/clip.mp4',
        displayName: 'clip.mp4',
      ),
    );
  });

  test('a_lost_image_is_no_lost_video', () {
    final result = lostVideoResultOf(
      LostDataResponse(
        type: RetrieveType.image,
        files: [XFile('/cache/picked/photo.jpg')],
      ),
    );

    expect(result, isA<NoLostVideo>());
  });

  test('a_lost_pick_that_had_failed_is_a_pick_failure', () {
    final response = LostDataResponse(
      type: RetrieveType.video,
      exception: PlatformException(code: 'already_active'),
    );

    expect(
      () => lostVideoResultOf(response),
      throwsA(isA<VideoPickFailedException>()),
    );
  });

  test('the_fake_picker_hands_back_a_lost_video', () async {
    const video = VideoPicked(path: '/cache/a.mp4', displayName: 'a.mp4');
    final picker = FakeVideoPicker()..lost = const LostVideoFound(video);

    final result = await picker.retrieveLostVideo();

    expect((result as LostVideoFound).video, video);
  });
}
