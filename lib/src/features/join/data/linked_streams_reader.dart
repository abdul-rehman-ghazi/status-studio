import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/linked_formats_json.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Reads a linked video's streams afresh (spec FR-37): their links expire
/// after some hours, so the ones read on From a link can't be reused.
class LinkedStreamsReader {
  const LinkedStreamsReader(this.ytDlp);

  final YtDlp ytDlp;

  /// Without JavaScript first, as FR-35 reads; with QuickJS when that run
  /// fails or finds no MP4 stream. Throws [VideoUnavailableException],
  /// [OfflineException], [SiteChangedException] or
  /// [NotDownloadableInPartsException].
  Future<LinkedFormats> read(LinkedVideo video) async {
    try {
      final quick = linkedFormatsFromYtDlpJson(
        await ytDlp.quickVideoInfo(video.pageUrl),
      );
      if (_hasMp4Streams(quick) || _hasWholeMp4(video, quick)) {
        return quick;
      }
    } on SiteChangedException {
      // The run with QuickJS below may still read it.
    }
    return linkedFormatsFromYtDlpJson(await ytDlp.videoInfo(video.pageUrl));
  }
}

bool _hasMp4Streams(LinkedFormats formats) =>
    formats.video.any((stream) => stream.isMp4) &&
    formats.audio.any((stream) => stream.isMp4);

/// Another site's whole file needs no QuickJS run (spec FR-50).
bool _hasWholeMp4(LinkedVideo video, LinkedFormats formats) =>
    !video.isYouTube && formats.whole.any((stream) => stream.isMp4);

final linkedStreamsReaderProvider = Provider<LinkedStreamsReader>(
  (ref) => LinkedStreamsReader(ref.watch(ytDlpProvider)),
);
