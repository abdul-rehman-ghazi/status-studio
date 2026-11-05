import 'package:status_studio/src/features/source/data/video_picker.dart';

/// Answers every pick with [result] (the default is the user cancelling)
/// and every lost-video check with [lost].
class FakeVideoPicker implements VideoPicker {
  FakeVideoPicker([this.result = const VideoPickCancelled()]);

  VideoPickResult result;
  LostVideoResult lost = const NoLostVideo();
  var picks = 0;

  @override
  Future<VideoPickResult> pickVideo() async {
    picks++;
    return result;
  }

  @override
  Future<LostVideoResult> retrieveLostVideo() async => lost;
}
