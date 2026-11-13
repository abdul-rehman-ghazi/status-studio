import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/mux_arguments.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/join/data/ranged_downloader.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/join/domain/download_cancel.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/segment_index.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';

const _firstHeadBytes = 64 * 1024;
const _maximumHeadBytes = 2 * 1024 * 1024;

/// Which stretch of which linked video to download, from which streams.
class CutRequest {
  const CutRequest({
    required this.youtubeId,
    required this.window,
    required this.streams,
  });

  final String youtubeId;

  /// In the linked video's time, margins included.
  final ClipWindow window;
  final CutStreams streams;
}

/// How a cut download reports back, and how it is stopped.
class CutDownloadWatch {
  const CutDownloadWatch({required this.cancel, required this.onBytes});

  final DownloadCancel cancel;

  /// Bytes received so far of the cut's total.
  final void Function(int receivedBytes, int totalBytes) onBytes;
}

/// One stream's part of a cut: where its bytes are and when it starts.
class _StreamPlan {
  const _StreamPlan({
    required this.url,
    required this.ranges,
    required this.segments,
  });

  final Uri url;
  final List<ByteRange> ranges;
  final List<MediaSegment> segments;

  int get totalBytes => ranges.fold(0, (sum, range) => sum + range.length);

  Duration get start => segments.first.start;

  Duration get end => segments.last.end;
}

/// Downloads only a stretch of a linked video (spec FR-37): the byte ranges
/// of the picture and sound segments around it, read from each stream's
/// segment index, muxed into one MP4 by stream copy. M7's clip preparer,
/// restored from `a5294bf^` and narrowed to linked videos.
class CutDownloader {
  CutDownloader({
    required this.downloader,
    required this.ffmpeg,
    required this.folder,
  });

  final RangedDownloader downloader;
  final FfmpegRunner ffmpeg;

  /// `cuts/` in the cache; a cut lives in `<YouTube ID>/` there.
  final Future<Directory> folder;

  /// A cut already downloaded from the same streams that covers the window
  /// is reused. Throws [NotDownloadableInPartsException],
  /// [ExpiredStreamUrlException], [DownloadCancelledException], or the
  /// typed I/O errors of `source_errors.dart`.
  Future<CutFile> download(CutRequest request, CutDownloadWatch watch) =>
      guardIo(() async {
        final kept = await _keptCovering(request);
        if (kept != null) {
          return kept;
        }
        try {
          return await _download(request, watch);
        } on NoSegmentIndexException {
          throw const NotDownloadableInPartsException('No segment index.');
        } on RangeNotSupportedException {
          throw const NotDownloadableInPartsException('No range requests.');
        }
      });

  Future<CutFile?> _keptCovering(CutRequest request) async {
    final cuts = await _cutsFolder(request.youtubeId);
    if (!await cuts.exists()) {
      return null;
    }
    await for (final entry in cuts.list()) {
      final kept = await _readKept(entry);
      if (kept != null &&
          kept.streamsKey == request.streams.key &&
          _covers(kept.covered, request.window)) {
        return kept;
      }
    }
    return null;
  }

  /// A cut's JSON is written last, so a cut with one is whole.
  Future<CutFile?> _readKept(FileSystemEntity entry) async {
    if (entry is! File || !entry.path.endsWith('.json')) {
      return null;
    }
    final video = File(entry.path.replaceFirst(RegExp(r'\.json$'), '.mp4'));
    if (!await video.exists()) {
      return null;
    }
    try {
      final json = jsonDecode(await entry.readAsString());
      return json is Map<String, Object?>
          ? CutFile.fromJson(video, json)
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<CutFile> _download(CutRequest request, CutDownloadWatch watch) async {
    final video = await _plan(request.streams.video.url, request.window);
    final audio = await _plan(request.streams.audio.url, request.window);
    final total = video.totalBytes + audio.totalBytes;
    final cuts = await _cutsFolder(request.youtubeId);
    final name = '${cuts.path}/${_nameOf(request)}';
    final videoFile = await downloader.downloadRanges(
      _rangedDownload(video, File('$name.video.mp4'), watch.cancel),
      onBytes: (received) => watch.onBytes(received, total),
    );
    final audioFile = await downloader.downloadRanges(
      _rangedDownload(audio, File('$name.audio.m4a'), watch.cancel),
      onBytes: (received) => watch.onBytes(video.totalBytes + received, total),
    );
    final fileStart = video.start < audio.start ? video.start : audio.start;
    final target = File('$name.mp4');
    await _mux(
      video: MuxInput(path: videoFile.path, delay: video.start - fileStart),
      audio: MuxInput(path: audioFile.path, delay: audio.start - fileStart),
      target: target,
    );
    final cut = CutFile(
      file: target,
      streamsKey: request.streams.key,
      fileStart: fileStart,
      covered: ClipWindow(
        start: video.start > audio.start ? video.start : audio.start,
        end: video.end < audio.end ? video.end : audio.end,
      ),
    );
    await File('$name.json').writeAsString(jsonEncode(cut.toJson()));
    return cut;
  }

  Future<_StreamPlan> _plan(Uri url, ClipWindow window) async {
    final index = await _readIndex(url);
    final segments = segmentsCovering(index, window);
    if (segments.isEmpty) {
      throw const NoSegmentIndexException();
    }
    return _StreamPlan(
      url: url,
      ranges: [index.init, mergedRange(segments)],
      segments: segments,
    );
  }

  /// Fetches the start of the stream, doubling the amount until the whole
  /// `sidx` box is in it; past 2 MiB the stream counts as having no index.
  Future<SegmentIndex> _readIndex(Uri url) async {
    var length = _firstHeadBytes;
    while (length <= _maximumHeadBytes) {
      final head = await downloader.fetchHead(url, length);
      try {
        return parseSegmentIndex(head);
      } on SegmentIndexNotFoundException catch (missing) {
        _requireMoreBytes(head, length);
        length = math.max(length * 2, missing.bytesNeeded);
      }
    }
    throw const NoSegmentIndexException();
  }

  Future<void> _mux({
    required MuxInput video,
    required MuxInput audio,
    required File target,
  }) async {
    final muxing = File('${target.path}.muxing.mp4');
    try {
      await ffmpeg.run(
        clipMuxArguments(video: video, audio: audio, outputPath: muxing.path),
      );
      await muxing.rename(target.path);
    } finally {
      await _deleteIfExists(muxing);
      await _deleteIfExists(File(video.path));
      await _deleteIfExists(File(audio.path));
    }
  }

  /// Deletes every cut downloaded from [youtubeId] (spec FR-44).
  Future<void> deleteCutsOf(String youtubeId) async {
    final cuts = await _cutsFolder(youtubeId);
    if (await cuts.exists()) {
      await cuts.delete(recursive: true);
    }
  }

  Future<Directory> _cutsFolder(String youtubeId) async =>
      Directory('${(await folder).path}/$youtubeId');
}

RangedDownload _rangedDownload(
  _StreamPlan plan,
  File target,
  DownloadCancel cancel,
) => RangedDownload(
  url: plan.url,
  ranges: plan.ranges,
  target: target,
  cancel: cancel,
);

bool _covers(ClipWindow outer, ClipWindow inner) =>
    outer.start <= inner.start && inner.end <= outer.end;

String _nameOf(CutRequest request) =>
    '${request.streams.key}_${request.window.start.inMilliseconds}'
    '-${request.window.end.inMilliseconds}';

/// A head shorter than asked for is the whole stream, so no `sidx` is
/// coming.
void _requireMoreBytes(Uint8List head, int asked) {
  if (head.length < asked) {
    throw const NoSegmentIndexException();
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

final cutDownloaderProvider = Provider<CutDownloader>(
  (ref) => CutDownloader(
    downloader: ref.watch(rangedDownloaderProvider),
    ffmpeg: ref.watch(ffmpegRunnerProvider),
    folder: getTemporaryDirectory().then(
      (cache) => Directory('${cache.path}/cuts'),
    ),
  ),
);
