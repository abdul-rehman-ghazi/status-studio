import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/stream_choice.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';

/// What the user said to "This site only offers the whole video" (spec
/// FR-50). Review cuts keeps the answer while it is open.
enum WholeVideoAnswer { notAsked, allowed }

/// "84 MB", or "size unknown" when neither yt-dlp nor the server says
/// (spec FR-50).
String wholeVideoSizeLabel(int? totalBytes) =>
    totalBytes == null ? 'size unknown' : '${(totalBytes / 1e6).round()} MB';

/// A site's whole video in place of its parts, and what the user said.
class WholeVideoOrder {
  const WholeVideoOrder({
    required this.request,
    required this.answer,
    required this.watch,
  });

  final WholeVideoRequest request;
  final WholeVideoAnswer answer;
  final CutDownloadWatch watch;
}

/// The whole video as one cut (spec FR-50): downloaded once the user
/// allows it, and reused without asking once in the cache (*Claude's
/// call*). Throws [WholeFileNeededException] until then.
Future<CutFile> fetchWholeVideo(
  CutDownloader cuts,
  WholeVideoOrder order,
) async {
  final request = order.request;
  if (order.answer != WholeVideoAnswer.allowed &&
      !await cuts.hasWhole(request)) {
    throw WholeFileNeededException(await cuts.wholeSizeOf(request.stream));
  }
  return cuts.downloadWhole(request, order.watch);
}

/// The stream for [video]'s whole file when its parts can't be fetched.
/// YouTube always offers parts, and its only files with both are 360p, so
/// its [partsFailure] stands (*Claude's call*, FR-50); so it does when the
/// site offers no MP4 file with both (HLS only).
StreamFormat wholeStreamOrThrow(
  LinkedVideo video,
  LinkedFormats formats,
  NotDownloadableInPartsException partsFailure,
) {
  if (video.isYouTube) {
    throw partsFailure;
  }
  try {
    return pickWholeStream(formats.whole);
  } on NotDownloadableInPartsException {
    throw partsFailure;
  }
}
