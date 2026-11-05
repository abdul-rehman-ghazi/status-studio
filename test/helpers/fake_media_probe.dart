import 'package:status_studio/src/core/ffmpeg/local_video_facts.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Reads every local video as [facts], as the real probe does: a video
/// without audio is refused. Throws [unreadable] instead when it is set.
class FakeMediaProbe extends MediaProbe {
  FakeMediaProbe({
    this.facts = const LocalVideoFacts(
      duration: Duration(seconds: 42),
      sizeBytes: 3 * 1024 * 1024,
      rotationDegrees: 0,
      storedWidth: 1080,
      storedHeight: 1920,
      hasAudio: true,
    ),
    this.unreadable,
  });

  LocalVideoFacts facts;
  VideoUnreadableException? unreadable;

  @override
  Future<LocalVideoFacts> readLocalVideo(String path) async {
    final failure = unreadable;
    if (failure != null) {
      throw failure;
    }
    return facts.requireAudio();
  }
}
