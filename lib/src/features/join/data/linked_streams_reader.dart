import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/linked_formats_json.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Reads a linked video's streams afresh (spec FR-37): their links expire
/// after some hours, so the ones read on From a link can't be reused.
class LinkedStreamsReader {
  const LinkedStreamsReader(this.ytDlp);

  final YtDlp ytDlp;

  /// Without JavaScript first, as FR-35 reads; with QuickJS when that run
  /// fails or finds no MP4 stream. Throws [VideoUnavailableException],
  /// [OfflineException], [YouTubeChangedException] or
  /// [NotDownloadableInPartsException].
  Future<LinkedFormats> read(String youtubeId) async {
    try {
      final quick = linkedFormatsFromYtDlpJson(
        await ytDlp.quickVideoInfo(youtubeId),
      );
      if (_hasMp4Streams(quick)) {
        return quick;
      }
    } on YouTubeChangedException {
      // The run with QuickJS below may still read it.
    }
    return linkedFormatsFromYtDlpJson(await ytDlp.videoInfo(youtubeId));
  }
}

bool _hasMp4Streams(LinkedFormats formats) =>
    formats.video.any((stream) => stream.isMp4) &&
    formats.audio.any((stream) => stream.isMp4);

final linkedStreamsReaderProvider = Provider<LinkedStreamsReader>(
  (ref) => LinkedStreamsReader(ref.watch(ytDlpProvider)),
);
