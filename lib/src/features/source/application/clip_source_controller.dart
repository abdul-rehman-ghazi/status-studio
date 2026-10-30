import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/single_flight.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/data/clip_source_preparer.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// How far one video's clip download has got, from 0 to 1.
final clipSourceProgressProvider =
    NotifierProvider.family<ClipSourceProgress, double, String>(
      ClipSourceProgress.new,
    );

class ClipSourceProgress extends Notifier<double> {
  ClipSourceProgress(this.videoId);

  final String videoId;

  @override
  double build() => 0;

  void report(double fraction) => state = fraction;
}

/// The downloaded clip window for preview and rendering, per video ID so
/// one reel never sees another's file. `null` until the first request.
final clipSourceProvider =
    AsyncNotifierProvider.family<ClipSourceController, ClipSource?, String>(
      ClipSourceController.new,
    );

class ClipSourceController extends AsyncNotifier<ClipSource?> {
  ClipSourceController(this.videoId);

  final String videoId;
  final _downloads = SingleFlight<ClipSource>();
  ClipRange? _latestClip;

  @override
  Future<ClipSource?> build() async => null;

  /// Makes sure a downloaded window covers [clip]: does nothing when the
  /// current one already does, shares a download already running for the
  /// same window, and retries after a failure.
  Future<void> prepareFor(SourceVideo video, ClipRange clip) async {
    if (video.videoId != videoId) {
      throw ArgumentError.value(video.videoId, 'video', 'is not $videoId');
    }
    _latestClip = clip;
    final current = state.value;
    if (!state.isLoading && current != null && current.window.covers(clip)) {
      return;
    }
    final window = clipWindowFor(clip, video.duration);
    final progress = ref.read(clipSourceProgressProvider(videoId).notifier);
    state = const AsyncLoading();
    progress.report(0);
    final result = await AsyncValue.guard<ClipSource?>(
      () => _downloads.run(
        '${window.start}-${window.end}',
        () => _prepare(video, clip, progress),
      ),
    );
    if (ref.mounted && _answersLatestRequest(result, clip)) {
      state = result;
    }
  }

  Future<ClipSource> _prepare(
    SourceVideo video,
    ClipRange clip,
    ClipSourceProgress progress,
  ) async {
    final cache = await ref.read(sourceCacheProvider.future);
    return ref
        .read(clipSourcePreparerProvider)
        .prepare(
          ClipPrepareRequest(video: video, clip: clip, cache: cache),
          onProgress: progress.report,
        );
  }

  /// A download for an older nudge must not replace one that the newest
  /// clip still needs.
  bool _answersLatestRequest(AsyncValue<ClipSource?> result, ClipRange clip) {
    final latest = _latestClip;
    if (latest == null || latest == clip) {
      return true;
    }
    return result.value?.window.covers(latest) ?? false;
  }
}
