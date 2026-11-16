import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/video_link.dart';

/// Reads a link into a [LinkedVideo] (spec FR-35, FR-50): without
/// JavaScript first, since that is about twice as fast on a mid-range phone,
/// and with QuickJS when that run can't read the video (§10 item 4).
class LinkedVideoReader {
  const LinkedVideoReader(this.ytDlp);

  final YtDlp ytDlp;

  /// Throws [InvalidLinkException], [VideoUnavailableException],
  /// [OfflineException] or [SiteChangedException].
  Future<LinkedVideo> read(String link) async {
    final pageUrl = parseVideoLink(link);
    try {
      return LinkedVideo.fromYtDlpJson(
        await ytDlp.quickVideoInfo(pageUrl),
        pastedPageUrl: pageUrl,
      );
    } on SiteChangedException {
      return LinkedVideo.fromYtDlpJson(
        await ytDlp.videoInfo(pageUrl),
        pastedPageUrl: pageUrl,
      );
    }
  }
}

final linkedVideoReaderProvider = Provider<LinkedVideoReader>(
  (ref) => LinkedVideoReader(ref.watch(ytDlpProvider)),
);
