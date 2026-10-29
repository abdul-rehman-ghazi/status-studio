import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

class FakeVideoSource implements VideoSource {
  const FakeVideoSource();

  @override
  Future<SourceVideo> fetchVideo(String videoId) async {
    return SourceVideo(
      videoId: videoId,
      title: 'Sample video',
      channel: 'Sample channel',
      duration: const Duration(minutes: 6, seconds: 48),
    );
  }
}
