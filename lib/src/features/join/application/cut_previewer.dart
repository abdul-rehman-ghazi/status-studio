import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/join/application/whole_video.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/data/kept_video_cut.dart';
import 'package:status_studio/src/features/join/data/linked_streams_reader.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/join/domain/download_cancel.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';

/// Stream links last some hours; an hour leaves a wide margin.
const _streamsKeptFor = Duration(hours: 1);

/// How much the Play sheet shows before and after a moment, so a nudge
/// can be heard (spec FR-39).
const previewMargin = Duration(seconds: 5);

/// Formats read for a video, and when.
typedef _ReadFormats = ({LinkedFormats formats, DateTime readAt});

/// One Play on a card, and what the user said to a whole video (spec
/// FR-50).
class PreviewOrder {
  const PreviewOrder({
    required this.source,
    required this.cut,
    this.wholeVideo = WholeVideoAnswer.notAsked,
  });

  final MomentSource source;
  final TopicCut cut;
  final WholeVideoAnswer wholeVideo;

  /// The same order for a nudged moment.
  PreviewOrder withCut(TopicCut moved) =>
      PreviewOrder(source: source, cut: moved, wholeVideo: wholeVideo);
}

/// A link's Play, with the link.
typedef _LinkedPreview = ({LinkedVideo video, PreviewOrder order});

/// Play on a card (spec FR-37, FR-39): the moment with [previewMargin]
/// around it, at up to 480p, downloaded into the cache as a cut is, and
/// reused when played again. A site without parts gives its whole video
/// once allowed, which Make the clip then reuses (FR-50).
class CutPreviewer {
  CutPreviewer({
    required this.streams,
    required this.cuts,
    required this.sources,
  });

  final LinkedStreamsReader streams;
  final CutDownloader cuts;

  /// A kept video plays from its own file, from the moment's start to its
  /// end; nothing is cut (spec FR-51).
  final Future<SourceCache> sources;

  /// Reading streams takes yt-dlp several seconds, so they are kept for
  /// the next card.
  final _read = <String, _ReadFormats>{};

  /// Throws as [CutDownloader.download] and [LinkedStreamsReader.read] do,
  /// and [WholeFileNeededException] until a whole video is allowed.
  Future<CutFile> prepare(PreviewOrder order) async => switch (order.source) {
    LocalMoments(:final video) => keptVideoCut(await sources, video),
    LinkedMoments(:final video) => _prepareLinked((video: video, order: order)),
  };

  Future<CutFile> _prepareLinked(_LinkedPreview preview) async {
    final video = preview.video;
    try {
      return await _prepareFrom(await _formatsFor(video), preview);
    } on ExpiredStreamUrlException {
      _read.remove(video.videoKey);
      return _prepareFrom(await _formatsFor(video), preview);
    }
  }

  Future<LinkedFormats> _formatsFor(LinkedVideo video) async {
    final kept = _read[video.videoKey];
    if (kept != null &&
        DateTime.now().difference(kept.readAt) < _streamsKeptFor) {
      return kept.formats;
    }
    final read = await streams.read(video);
    _read[video.videoKey] = (formats: read, readAt: DateTime.now());
    return read;
  }

  Future<CutFile> _prepareFrom(
    LinkedFormats formats,
    _LinkedPreview preview,
  ) async {
    try {
      return await _downloadPart(preview, streamsForPreview(formats));
    } on NotDownloadableInPartsException catch (partsFailure) {
      final video = preview.video;
      final stream = wholeStreamOrThrow(video, formats, partsFailure);
      return fetchWholeVideo(
        cuts,
        WholeVideoOrder(
          request: WholeVideoRequest(video: video, stream: stream),
          answer: preview.order.wholeVideo,
          watch: _unwatched(),
        ),
      );
    }
  }

  Future<CutFile> _downloadPart(_LinkedPreview preview, CutStreams streams) =>
      cuts.download(
        CutRequest(
          videoKey: preview.video.videoKey,
          window: previewWindowFor(preview.order.cut, preview.video.duration),
          streams: streams,
        ),
        _unwatched(),
      );
}

/// Play shows no bytes and has no Cancel.
CutDownloadWatch _unwatched() =>
    CutDownloadWatch(cancel: DownloadCancel(), onBytes: (_, _) {});

/// [cut] with [previewMargin] on both sides, clamped to the video.
ClipWindow previewWindowFor(TopicCut cut, Duration videoLength) {
  final start = cut.start - previewMargin;
  final end = cut.end + previewMargin;
  return ClipWindow(
    start: start < Duration.zero ? Duration.zero : start,
    end: end > videoLength ? videoLength : end,
  );
}

final cutPreviewerProvider = Provider<CutPreviewer>(
  (ref) => CutPreviewer(
    streams: ref.watch(linkedStreamsReaderProvider),
    cuts: ref.watch(cutDownloaderProvider),
    sources: ref.watch(sourceCacheProvider.future),
  ),
);
