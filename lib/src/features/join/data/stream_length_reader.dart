import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/domain/linked_formats_json.dart';
import 'package:status_studio/src/features/join/domain/segment_index.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// The length of a linked video yt-dlp gives none for (spec FR-50, M74):
/// Instagram's answer to a logged-out request has none, but its streams
/// state it in their first bytes.
class StreamLengthReader {
  const StreamLengthReader(this.cuts);

  final CutDownloader cuts;

  /// Tries the smallest MP4 sound stream, picture stream and whole file,
  /// in that order: one or two small range requests each. Throws
  /// [SiteChangedException] when none states a length, and the network
  /// errors of [CutDownloader].
  Future<Duration> lengthOf(Map<String, Object?> info) async {
    final formats = linkedFormatsFromYtDlpJson(info);
    for (final stream in _smallestOfEachKind(formats)) {
      try {
        return await cuts.streamLength(stream);
      } on NoMovieLengthException {
        // The next kind may state it.
      }
    }
    throw const SiteChangedException(
      'Neither yt-dlp nor the streams give the length.',
    );
  }
}

List<StreamFormat> _smallestOfEachKind(LinkedFormats formats) => [
  for (final kind in [formats.audio, formats.video, formats.whole])
    ?_smallestMp4(kind),
];

StreamFormat? _smallestMp4(List<StreamFormat> streams) {
  final mp4 = streams.where((stream) => stream.isMp4);
  if (mp4.isEmpty) {
    return null;
  }
  return mp4.reduce((a, b) => _sizeRank(b) < _sizeRank(a) ? b : a);
}

/// The lowest picture, then the lowest bitrate, comes first.
int _sizeRank(StreamFormat stream) =>
    stream.height * 100000000 + stream.bitrate;

final streamLengthReaderProvider = Provider<StreamLengthReader>(
  (ref) => StreamLengthReader(ref.watch(cutDownloaderProvider)),
);
