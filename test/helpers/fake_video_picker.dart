import 'package:status_studio/src/features/source/data/video_picker.dart';

/// Answers every pick with [result]; the default is the user cancelling.
class FakeVideoPicker implements VideoPicker {
  FakeVideoPicker([this.result = const VideoPickCancelled()]);

  VideoPickResult result;
  var picks = 0;

  @override
  Future<VideoPickResult> pickVideo() async {
    picks++;
    return result;
  }
}
