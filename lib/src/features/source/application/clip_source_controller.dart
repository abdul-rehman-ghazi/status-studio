import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
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

  /// The one download running for this video. Never completes with an
  /// error: failures land in [state].
  Future<void>? _running;
  ClipRange? _latestClip;

  @override
  Future<ClipSource?> build() async => null;

  /// Makes sure a downloaded window covers [clip]. Only one download runs
  /// at a time; a request made meanwhile waits for it, and only the newest
  /// one starts another download if it's still needed.
  Future<void> prepareFor(SourceVideo video, ClipRange clip) async {
    if (video.videoId != videoId) {
      throw ArgumentError.value(video.videoId, 'video', 'is not $videoId');
    }
    _latestClip = clip;
    for (var running = _running; running != null; running = _running) {
      await running;
      if (_latestClip != clip) {
        return;
      }
    }
    if (_isCovered(clip)) {
      return;
    }
    final download = _download(video, clip);
    _running = download;
    await download;
    _running = null;
  }

  /// Only a successful state counts: after a failure Riverpod keeps the old
  /// value, but the screen shows the error, so it must be fetched again.
  bool _isCovered(ClipRange clip) => switch (state) {
    AsyncData(value: final current?) => current.window.covers(clip),
    _ => false,
  };

  Future<void> _download(SourceVideo video, ClipRange clip) async {
    final progress = ref.read(clipSourceProgressProvider(videoId).notifier);
    state = const AsyncLoading();
    progress.report(0);
    final result = await AsyncValue.guard<ClipSource?>(() async {
      final cache = await ref.read(sourceCacheProvider.future);
      return ref
          .read(clipSourcePreparerProvider)
          .prepare(
            ClipPrepareRequest(video: video, clip: clip, cache: cache),
            onProgress: progress.report,
          );
    });
    if (ref.mounted) {
      state = result;
    }
  }
}
