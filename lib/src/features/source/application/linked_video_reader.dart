import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/youtube_link.dart';

/// Reads a YouTube link into a [LinkedVideo] (spec FR-35): without
/// JavaScript first, since that is about twice as fast on a mid-range phone,
/// and with QuickJS when that run can't read the video (§10 item 4).
class LinkedVideoReader {
  const LinkedVideoReader(this.ytDlp);

  final YtDlp ytDlp;

  /// Throws [InvalidYouTubeLinkException], [VideoUnavailableException],
  /// [OfflineException] or [YouTubeChangedException].
  Future<LinkedVideo> read(String link) async {
    final videoId = parseYouTubeVideoId(link);
    try {
      return LinkedVideo.fromYtDlpJson(await ytDlp.quickVideoInfo(videoId));
    } on YouTubeChangedException {
      return LinkedVideo.fromYtDlpJson(await ytDlp.videoInfo(videoId));
    }
  }
}

final linkedVideoReaderProvider = Provider<LinkedVideoReader>(
  (ref) => LinkedVideoReader(ref.watch(ytDlpProvider)),
);
