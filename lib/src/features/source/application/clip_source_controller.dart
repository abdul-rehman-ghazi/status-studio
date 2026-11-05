import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// The kept video for preview and rendering, per video ID so one reel never
/// sees another's file. `null` until [ClipSourceController.open] has run.
final clipSourceProvider =
    AsyncNotifierProvider.family<ClipSourceController, ClipSource?, String>(
      ClipSourceController.new,
    );

/// Opens the video the user brought in (spec FR-1, FR-5). Nothing is
/// downloaded or cut: the preview and the render both use the kept file, and
/// its window is the whole video, so a nudge never needs a new file.
class ClipSourceController extends AsyncNotifier<ClipSource?> {
  ClipSourceController(this.videoId);

  final String videoId;

  /// The one open running for this video. Never completes with an error:
  /// failures land in [state].
  Future<void>? _opening;

  @override
  Future<ClipSource?> build() async => null;

  /// Makes the kept file of [video] the source. A second call while one is
  /// running waits for it, and one made after it succeeded does nothing; after
  /// a failure it tries again.
  Future<void> open(SourceVideo video) async {
    if (video.videoId != videoId) {
      throw ArgumentError.value(video.videoId, 'video', 'is not $videoId');
    }
    if (state.value != null) {
      return;
    }
    if (_opening case final running?) {
      return running;
    }
    final opening = _open(video);
    _opening = opening;
    await opening;
    _opening = null;
  }

  Future<void> _open(SourceVideo video) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard<ClipSource?>(
      () => _keptSource(video),
    );
    if (ref.mounted) {
      state = result;
    }
  }

  Future<ClipSource> _keptSource(SourceVideo video) async {
    final cache = await ref.read(sourceCacheProvider.future);
    final kept = cache.keptLocalVideos(videoId);
    if (kept.isEmpty) {
      throw KeptVideoMissingException(videoId);
    }
    return ClipSource(
      file: kept.first,
      offset: Duration.zero,
      window: ClipWindow(start: Duration.zero, end: video.duration),
    );
  }
}
