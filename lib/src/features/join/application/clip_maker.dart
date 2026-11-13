import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/join/data/clip_joiner.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/join/data/linked_streams_reader.dart';
import 'package:status_studio/src/features/join/domain/cut_window.dart';
import 'package:status_studio/src/features/join/domain/download_cancel.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/join_plan.dart';
import 'package:status_studio/src/features/join/domain/linked_clip.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

/// What Make the clip was asked for: the ticked cuts in the list's order.
class ClipOrder {
  const ClipOrder({
    required this.request,
    required this.cuts,
    required this.transition,
  });

  final TopicRequest request;
  final List<TopicCut> cuts;
  final ClipTransition transition;
}

class ClipMakerServices {
  const ClipMakerServices({
    required this.streams,
    required this.cuts,
    required this.joiner,
    required this.importer,
    required this.links,
    required this.joinsFolder,
  });

  final LinkedStreamsReader streams;
  final CutDownloader cuts;
  final ClipJoiner joiner;
  final Future<LocalVideoImporter> importer;
  final LinkedClipStore links;

  /// In the cache, which the importer owns, so the joined file is moved
  /// into `sources/` rather than copied.
  final Future<Directory> joinsFolder;
}

/// One run of Make the clip: what Cancel must stop.
class _MakingRun {
  _MakingRun(this.onProgress);

  final void Function(MakingProgress progress) onProgress;
  final cancel = DownloadCancel();
  var joining = false;
}

/// Make the clip (spec FR-37): fresh stream links, each ticked cut
/// downloaded with its margins, the join, then the joined file kept like a
/// shared video with its link facts beside it.
class ClipMaker {
  ClipMaker(this._services);

  final ClipMakerServices _services;
  _MakingRun? _run;

  /// Throws the typed errors of `join_errors.dart` and `source_errors.dart`
  /// ([DownloadCancelledException] after [cancel]). Finished cuts stay in
  /// the cache, so another try downloads only the rest.
  Future<SourceVideo> make(
    ClipOrder order,
    void Function(MakingProgress progress) onProgress,
  ) async {
    final run = _run = _MakingRun(onProgress);
    try {
      final youtubeId = order.request.video.videoId;
      run.onProgress(const ReadingStreams());
      var streams = streamsForClip(await _services.streams.read(youtubeId));
      final downloaded = <DownloadedCut>[];
      for (var index = 0; index < order.cuts.length; index++) {
        final download = _CutDownload(order, index, run);
        try {
          downloaded.add(await download.fetch(_services.cuts, streams));
        } on ExpiredStreamUrlException {
          streams = await _freshStreams(youtubeId);
          downloaded.add(await _fetchAgain(download, streams));
        }
      }
      final plan = planJoin(downloaded, order.transition);
      final joined = await _join(plan, streams, run);
      run.onProgress(const KeepingClip());
      return await _keep(joined, order, plan);
    } finally {
      if (identical(_run, run)) {
        _run = null;
      }
    }
  }

  /// Stops the run: the download at its next chunk, or the join at once.
  Future<void> cancel() async {
    final run = _run;
    if (run == null) {
      return;
    }
    run.cancel.cancel();
    if (run.joining) {
      await _services.joiner.cancel();
    }
  }

  Future<CutStreams> _freshStreams(String youtubeId) async =>
      streamsForClip(await _services.streams.read(youtubeId));

  /// Links that expire again right after a fresh read count as a YouTube
  /// change, which a newer yt-dlp may handle (spec §8).
  Future<DownloadedCut> _fetchAgain(
    _CutDownload download,
    CutStreams streams,
  ) async {
    try {
      return await download.fetch(_services.cuts, streams);
    } on ExpiredStreamUrlException catch (error) {
      throw YouTubeChangedException('Stream links keep expiring: $error');
    }
  }

  Future<File> _join(JoinPlan plan, CutStreams streams, _MakingRun run) async {
    run.cancel.throwIfCancelled();
    final folder = await _services.joinsFolder;
    await folder.create(recursive: true);
    final output = File(
      '${folder.path}/joined_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    run
      ..joining = true
      ..onProgress(const JoiningCuts(0));
    try {
      await _services.joiner.join(
        plan,
        output.path,
        (fraction) => run.onProgress(JoiningCuts(fraction)),
      );
    } on JoinFailedException {
      run.cancel.throwIfCancelled();
      if (!streams.video.isH264) {
        throw const CutsNotDecodableException('The phone decodes no AV1.');
      }
      rethrow;
    } finally {
      run.joining = false;
    }
    return output;
  }

  Future<SourceVideo> _keep(File joined, ClipOrder order, JoinPlan plan) async {
    final importer = await _services.importer;
    // The extension names the file type; the rest becomes the video's
    // name in Recent.
    final video = await importer.importVideo(
      path: joined.path,
      displayName: '${order.request.topic.trim()}.mp4',
    );
    final linked = order.request.video;
    await _services.links.save(
      video.videoId,
      LinkedClip(
        youtubeId: linked.videoId,
        title: linked.title,
        channel: linked.channel,
        topic: order.request.topic.trim(),
        outputLanguage: order.request.outputLanguage,
        transition: order.transition,
        joinTimes: plan.joinTimes,
      ),
    );
    return video;
  }
}

/// One cut's download with its progress: number, size and speed.
class _CutDownload {
  _CutDownload(this.order, this.index, this.run);

  final ClipOrder order;
  final int index;
  final _MakingRun run;
  final _clock = Stopwatch();

  Future<DownloadedCut> fetch(CutDownloader cuts, CutStreams streams) async {
    final cut = order.cuts[index];
    _clock
      ..reset()
      ..start();
    _report(0, 0);
    final file = await cuts.download(
      CutRequest(
        youtubeId: order.request.video.videoId,
        window: downloadWindowFor(
          cut,
          order.transition,
          order.request.video.duration,
        ),
        streams: streams,
      ),
      CutDownloadWatch(cancel: run.cancel, onBytes: _report),
    );
    return DownloadedCut(cut: cut, file: file);
  }

  void _report(int receivedBytes, int totalBytes) {
    final seconds = _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
    run.onProgress(
      DownloadingCut(
        number: index + 1,
        count: order.cuts.length,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        bytesPerSecond: seconds > 0 ? receivedBytes / seconds : 0,
      ),
    );
  }
}

final clipMakerProvider = Provider<ClipMaker>(
  (ref) => ClipMaker(
    ClipMakerServices(
      streams: ref.watch(linkedStreamsReaderProvider),
      cuts: ref.watch(cutDownloaderProvider),
      joiner: ref.watch(clipJoinerProvider),
      importer: ref.watch(localVideoImporterProvider.future),
      links: ref.watch(linkedClipStoreProvider),
      joinsFolder: getTemporaryDirectory().then(
        (cache) => Directory('${cache.path}/joins'),
      ),
    ),
  ),
);
