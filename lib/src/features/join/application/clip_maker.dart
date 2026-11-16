import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/join/application/whole_video.dart';
import 'package:status_studio/src/features/join/data/clip_joiner.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/data/kept_video_cut.dart';
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
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

/// What Make the clip was asked for: the ticked cuts in the list's order.
class ClipOrder {
  const ClipOrder({
    required this.request,
    required this.cuts,
    required this.transition,
    this.wholeVideo = WholeVideoAnswer.notAsked,
  });

  /// Use the whole video on From a link (spec FR-52): one cut from start
  /// to end, downloaded without asking, since the user asked for all of it.
  ClipOrder.wholeVideo(this.request)
    : cuts = [
        TopicCut(start: Duration.zero, end: request.source.duration, text: ''),
      ],
      transition = ClipTransition.cut,
      wholeVideo = WholeVideoAnswer.allowed;

  final TopicRequest request;
  final List<TopicCut> cuts;
  final ClipTransition transition;

  /// Whether a site without parts may give its whole video (spec FR-50).
  final WholeVideoAnswer wholeVideo;

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
/// [pictureIsH264] is false only for an AV1 picture, which a phone may not
/// decode for the join.
typedef _FetchedCuts = ({List<DownloadedCut> cuts, bool pictureIsH264});

class ClipMakerServices {
  const ClipMakerServices({
    required this.streams,
    required this.cuts,
    required this.joiner,
    required this.importer,
    required this.links,
    required this.joinsFolder,
    required this.sources,
  });

  final LinkedStreamsReader streams;
  final CutDownloader cuts;
  final ClipJoiner joiner;
  final Future<LocalVideoImporter> importer;
  final LinkedClipStore links;

  /// In the cache, which the importer owns, so the joined file is moved
  /// into `sources/` rather than copied.
  final Future<Directory> joinsFolder;

  /// Where a kept video's file is (spec FR-51).
  final Future<SourceCache> sources;
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
      if (order.request.source case LocalMoments(:final video)) {
        return await _makeFromKept(order, video, run);
      }
      final fetched = await _downloadCuts(order, run);
      if (fetched.cuts case [final only] when fetched.pictureIsH264) {
        return await _keepOne(only, order, run);
      }
      return await _joinAndKeep(fetched, order, run);
    } finally {
      if (identical(_run, run)) {
        _run = null;
      }
    }
  }

  /// Nothing downloads (spec FR-51): each cut is the kept file itself. One
  /// moment opens on the kept video at the moment, with no copy; several
  /// join as FR-37 joins.
  Future<MadeClip> _makeFromKept(
    ClipOrder order,
    SourceVideo video,
    _MakingRun run,
  ) async {
    if (order.cuts case [final only]) {
      return MadeClip(
        video: video,
        clip: _withinPlayable(
          ClipRange(start: only.start, end: only.end),
          video,
        ),
      );
    }
    final kept = keptVideoCut(await _services.sources, video);
    final cuts = [
      for (final cut in order.cuts) DownloadedCut(cut: cut, file: kept),
    ];
    return _joinAndKeep((cuts: cuts, pictureIsH264: true), order, run);
  }

  /// The parts around each cut; the whole video for a site that offers no
  /// parts (spec FR-50).
  Future<_FetchedCuts> _downloadCuts(ClipOrder order, _MakingRun run) async {
    final video = _linkedVideoOf(order);
    run.onProgress(const ReadingStreams());
    final formats = await _services.streams.read(video);
    try {
      return await _downloadParts(order, run, streamsForClip(formats));
    } on NotDownloadableInPartsException catch (partsFailure) {
      final stream = wholeStreamOrThrow(video, formats, partsFailure);
      return _downloadWhole(order, run, stream);
    }
  }

  Future<_FetchedCuts> _downloadParts(
    ClipOrder order,
    _MakingRun run,
    CutStreams firstStreams,
  ) async {
    final video = _linkedVideoOf(order);
    var streams = firstStreams;
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
    return (cuts: downloaded, pictureIsH264: streams.video.isH264);
  }

  /// Every cut is a stretch of the one file; its bytes show as one cut's.
  Future<_FetchedCuts> _downloadWhole(
    ClipOrder order,
    _MakingRun run,
    StreamFormat stream,
  ) async {
    final clock = Stopwatch()..start();
    final file = await fetchWholeVideo(
      _services.cuts,
      WholeVideoOrder(
        request: WholeVideoRequest(
          video: _linkedVideoOf(order),
          stream: stream,
        ),
        answer: order.wholeVideo,
        watch: CutDownloadWatch(
          cancel: run.cancel,
          onBytes: (received, total) =>
              run.onProgress(_downloadingOne(received, total, clock)),
        ),
      ),
    );
    return (
      cuts: [for (final cut in order.cuts) DownloadedCut(cut: cut, file: file)],
      pictureIsH264: stream.isH264,
    );
  }

  Future<MadeClip> _joinAndKeep(
    _FetchedCuts fetched,
    ClipOrder order,
    _MakingRun run,
  ) async {
    final plan = planJoin(fetched.cuts, order.transition);
    final joined = await _join(plan, fetched, run);
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
  Future<File> _join(
    JoinPlan plan,
    _FetchedCuts fetched,
    _MakingRun run,
  ) async {
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
      if (!fetched.pictureIsH264) {
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
      displayName: '${order.request.source.title}.mp4',
    );
    final source = order.request.source;
    await _services.links.save(
      video.videoId,
      LinkedClip(
        videoKey: source.key,
        title: source.title,
        channel: switch (source) {
          LinkedMoments(:final video) => video.channel,
          LocalMoments() => '',
        },
        sourceKind: source.kind,
        outputLanguage: order.request.outputLanguage,
        transition: order.transition,
        joinTimes: layout.joinTimes,
        cuts: layout.cuts,
      ),
    );
    return video;
  }
}

/// Only a link's cuts download.
LinkedVideo _linkedVideoOf(ClipOrder order) => switch (order.request.source) {
  LinkedMoments(:final video) => video,
  LocalMoments() => throw UnsupportedError('A kept video has no link.'),
};

DownloadingCut _downloadingOne(
  int receivedBytes,
  int totalBytes,
  Stopwatch clock,
) {
  final seconds = clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
  return DownloadingCut(
    number: 1,
    count: 1,
    receivedBytes: receivedBytes,
    totalBytes: totalBytes,
    bytesPerSecond: seconds > 0 ? receivedBytes / seconds : 0,
  );
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
        videoKey: order.request.source.key,
        window: downloadWindowFor(
          cut,
          order.margin,
          order.request.source.duration,
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
      sources: ref.watch(sourceCacheProvider.future),
    ),
  ),
);
