import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/data/linked_streams_reader.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/join/domain/download_cancel.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';

/// Stream links last some hours; an hour leaves a wide margin.
const _streamsKeptFor = Duration(hours: 1);

/// How much the Play sheet shows before and after a moment, so a nudge
/// can be heard (spec FR-39).
const previewMargin = Duration(seconds: 5);

/// Streams read for a video, and when.
typedef _ReadStreams = ({CutStreams streams, DateTime readAt});

/// Play on a card (spec FR-37, FR-39): the moment with [previewMargin]
/// around it, at up to 480p, downloaded into the cache as a cut is, and
/// reused when played again.
class CutPreviewer {
  CutPreviewer({required this.streams, required this.cuts});

  final LinkedStreamsReader streams;
  final CutDownloader cuts;

  /// Reading streams takes yt-dlp several seconds, so they are kept for
  /// the next card.
  final _read = <String, _ReadStreams>{};

  /// Throws as [CutDownloader.download] and [LinkedStreamsReader.read] do.
  Future<CutFile> prepare(LinkedVideo video, TopicCut cut) async {
    try {
      return await _download(video, cut, await _streamsFor(video));
    } on ExpiredStreamUrlException {
      _read.remove(video.videoKey);
      return _download(video, cut, await _streamsFor(video));
    }
  }

  Future<CutStreams> _streamsFor(LinkedVideo video) async {
    final kept = _read[video.videoKey];
    if (kept != null &&
        DateTime.now().difference(kept.readAt) < _streamsKeptFor) {
      return kept.streams;
    }
    final read = streamsForPreview(await streams.read(video));
    _read[video.videoKey] = (streams: read, readAt: DateTime.now());
    return read;
  }

  Future<CutFile> _download(
    LinkedVideo video,
    TopicCut cut,
    CutStreams streams,
  ) => cuts.download(
    CutRequest(
      videoKey: video.videoKey,
      window: previewWindowFor(cut, video.duration),
      streams: streams,
    ),
    CutDownloadWatch(cancel: DownloadCancel(), onBytes: (_, _) {}),
  );
}

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
  ),
);
