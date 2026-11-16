import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/join/data/clip_joiner.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/join/data/linked_streams_reader.dart';
import 'package:status_studio/src/features/join/domain/cut_window.dart';
import 'package:status_studio/src/features/join/domain/download_cancel.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/join_plan.dart';
import 'package:status_studio/src/features/join/domain/joined_cut.dart';
import 'package:status_studio/src/features/join/domain/linked_clip.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
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

  /// How far each cut is downloaded past its ends: one moment has nothing
  /// to blend into (spec FR-46).
  Duration get margin =>
      cuts.length == 1 ? Duration.zero : marginFor(transition);
}

/// The kept clip and the stretch of it Fine-tune opens on: the whole file
/// for joined cuts, the moment's place in its file for one (spec FR-46).
class MadeClip {
  const MadeClip({required this.video, required this.clip});

  final SourceVideo video;
  final ClipRange clip;
}

/// What a kept clip's link facts record of how its cuts were laid out.
typedef _CutLayout = ({List<Duration> joinTimes, List<JoinedCut> cuts});

/// The downloaded cuts and the streams they came from, the last ones read.
typedef _FetchedCuts = ({List<DownloadedCut> cuts, CutStreams streams});

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
/// shared video with its link facts beside it. One H.264 moment is kept
/// as downloaded, without a join (FR-46).
class ClipMaker {
  ClipMaker(this._services);

  final ClipMakerServices _services;
  _MakingRun? _run;

  /// Throws the typed errors of `join_errors.dart` and `source_errors.dart`
  /// ([DownloadCancelledException] after [cancel]). Finished cuts stay in
  /// the cache, so another try downloads only the rest.
  Future<MadeClip> make(
    ClipOrder order,
    void Function(MakingProgress progress) onProgress,
  ) async {
    final run = _run = _MakingRun(onProgress);
    try {
      final fetched = await _downloadCuts(order, run);
      if (fetched.cuts case [final only] when fetched.streams.video.isH264) {
        return await _keepOne(only, order, run);
      }
      return await _joinAndKeep(fetched, order, run);
    } finally {
      if (identical(_run, run)) {
        _run = null;
      }
    }
  }

  Future<_FetchedCuts> _downloadCuts(ClipOrder order, _MakingRun run) async {
    final video = order.request.video;
    run.onProgress(const ReadingStreams());
    var streams = streamsForClip(await _services.streams.read(video));
    final downloaded = <DownloadedCut>[];
    for (var index = 0; index < order.cuts.length; index++) {
      final download = _CutDownload(order, index, run);
      try {
        downloaded.add(await download.fetch(_services.cuts, streams));
      } on ExpiredStreamUrlException {
        streams = await _freshStreams(video);
        downloaded.add(await _fetchAgain(download, streams));
      }
    }
    return (cuts: downloaded, streams: streams);
  }

  Future<MadeClip> _joinAndKeep(
    _FetchedCuts fetched,
    ClipOrder order,
    _MakingRun run,
  ) async {
    final plan = planJoin(fetched.cuts, order.transition);
    final joined = await _join(plan, fetched.streams, run);
    run.onProgress(const KeepingClip());
    final video = await _keep(joined, order, (
      joinTimes: plan.joinTimes,
      cuts: plan.cuts,
    ));
    return MadeClip(
      video: video,
      clip: ClipRange(start: video.pictureStart, end: video.duration),
    );
  }

  /// The cut file is copied, not moved, so it stays in the cache for
  /// another Make the clip (spec FR-46).
  Future<MadeClip> _keepOne(
    DownloadedCut downloaded,
    ClipOrder order,
    _MakingRun run,
  ) async {
    run.cancel.throwIfCancelled();
    run.onProgress(const KeepingClip());
    final file = downloaded.file;
    final cut = downloaded.cut;
    final copy = await file.file.copy((await _newJoinedFile()).path);
    final clip = ClipRange(
      start: file.positionOf(cut.start),
      end: file.positionOf(cut.end),
    );
    final video = await _keep(copy, order, (
      joinTimes: const [],
      cuts: [
        JoinedCut(
          sourceStart: cut.start,
          sourceEnd: cut.end,
          joinedStart: clip.start,
        ),
      ],
    ));
    return MadeClip(video: video, clip: _withinPlayable(clip, video));
  }

  /// The probed file may start its picture later or end sooner than the
  /// segment index said.
  ClipRange _withinPlayable(ClipRange clip, SourceVideo video) {
    final started = clip.startingNoEarlierThan(video.pictureStart);
    return started.end > video.duration
        ? started.copyWith(end: video.duration)
        : started;
  }

  Future<File> _newJoinedFile() async {
    final folder = await _services.joinsFolder;
    await folder.create(recursive: true);
    return File(
      '${folder.path}/joined_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
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

  Future<CutStreams> _freshStreams(LinkedVideo video) async =>
      streamsForClip(await _services.streams.read(video));

  /// Links that expire again right after a fresh read count as a site
  /// change, which a newer yt-dlp may handle (spec §8).
  Future<DownloadedCut> _fetchAgain(
    _CutDownload download,
    CutStreams streams,
  ) async {
    try {
      return await download.fetch(_services.cuts, streams);
    } on ExpiredStreamUrlException catch (error) {
      throw SiteChangedException('Stream links keep expiring: $error');
    }
  }

  /// One cut reaches here only with an AV1 picture, which the join writes
  /// as H.264 (spec FR-46).
  Future<File> _join(JoinPlan plan, CutStreams streams, _MakingRun run) async {
    run.cancel.throwIfCancelled();
    final output = await _newJoinedFile();
    final MakingProgress Function(double fraction) step = plan.cuts.length == 1
        ? ConvertingCut.new
        : JoiningCuts.new;
    run
      ..joining = true
      ..onProgress(step(0));
    try {
      await _services.joiner.join(
        plan,
        output.path,
        (fraction) => run.onProgress(step(fraction)),
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

  Future<SourceVideo> _keep(
    File joined,
    ClipOrder order,
    _CutLayout layout,
  ) async {
    final importer = await _services.importer;
    // The extension names the file type; the rest becomes the video's
    // name in Recent.
    final video = await importer.importVideo(
      path: joined.path,
      displayName: '${order.request.video.title}.mp4',
    );
    final linked = order.request.video;
    await _services.links.save(
      video.videoId,
      LinkedClip(
        videoKey: linked.videoKey,
        title: linked.title,
        channel: linked.channel,
        outputLanguage: order.request.outputLanguage,
        transition: order.transition,
        joinTimes: layout.joinTimes,
        cuts: layout.cuts,
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
        videoKey: order.request.video.videoKey,
        window: downloadWindowFor(
          cut,
          order.margin,
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
