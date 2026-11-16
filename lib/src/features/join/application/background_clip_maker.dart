import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/background/application/background_work.dart';
import 'package:status_studio/src/features/join/application/clip_maker.dart';
import 'package:status_studio/src/features/join/application/clip_notices.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';

/// Make the clip kept running when the user leaves the app (spec FR-16,
/// FR-37): the foreground service and its notification while it runs, and
/// how it ended when the app isn't on screen. Review cuts carries on to
/// Fine-tune meanwhile, so the app comes back there.
class BackgroundClipMaker {
  const BackgroundClipMaker({required this.maker, required this.background});

  final ClipMaker maker;
  final BackgroundWork background;

  /// As [ClipMaker.make]; a cancel ends the notification quietly. One
  /// moment of a kept video opens at once, so it shows none (spec FR-51).
  Future<MadeClip> make(
    ClipOrder order,
    void Function(MakingProgress progress) onProgress,
  ) async {
    final source = order.request.source;
    if (source is LocalMoments && order.cuts.length == 1) {
      return maker.make(order, onProgress);
    }
    final notices = ClipNotices(source.title);
    background.showProgress(notices.job, switch (source) {
      LinkedMoments() => notices.starting,
      LocalMoments() => notices.progress(const JoiningCuts(0)),
    });
    try {
      final made = await maker.make(order, (progress) {
        background.showProgress(notices.job, notices.progress(progress));
        onProgress(progress);
      });
      background.finish(notices.job, notices.done);
      return made;
    } on DownloadCancelledException {
      background.cancel(notices.job);
      rethrow;
    } on WholeFileNeededException {
      // Review cuts asks on screen; nothing failed (spec FR-50).
      background.cancel(notices.job);
      rethrow;
    } on Object catch (error) {
      background.finish(notices.job, notices.failed(error));
      rethrow;
    }
  }

  Future<void> cancel() => maker.cancel();
}

final backgroundClipMakerProvider = Provider<BackgroundClipMaker>(
  (ref) => BackgroundClipMaker(
    maker: ref.watch(clipMakerProvider),
    background: ref.watch(backgroundWorkProvider),
  ),
);
