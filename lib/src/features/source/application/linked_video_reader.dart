import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/data/stream_length_reader.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/video_link.dart';

/// Reads a link into a [LinkedVideo] (spec FR-35, FR-50): without
/// JavaScript first, since that is about twice as fast on a mid-range phone,
/// and with QuickJS when that run can't read the video (§10 item 4).
class LinkedVideoReader {
  const LinkedVideoReader(this.ytDlp, {required this.lengths});

  final YtDlp ytDlp;

  /// Measures a length yt-dlp leaves out (M74).
  final StreamLengthReader lengths;

  /// Throws [InvalidLinkException], [VideoUnavailableException],
  /// [OfflineException] or [SiteChangedException].
  Future<LinkedVideo> read(String link) async {
    final pageUrl = parseVideoLink(link);
    try {
      return await _videoFrom(await ytDlp.quickVideoInfo(pageUrl), pageUrl);
    } on SiteChangedException {
      return _videoFrom(await ytDlp.videoInfo(pageUrl), pageUrl);
    }
  }

  Future<LinkedVideo> _videoFrom(
    Map<String, Object?> info,
    String pageUrl,
  ) async => LinkedVideo.fromYtDlpJson(
    await _withLength(info),
    pastedPageUrl: pageUrl,
  );

  /// Without formats there is nothing to measure; [LinkedVideo] then says
  /// so.
  Future<Map<String, Object?>> _withLength(Map<String, Object?> info) async {
    if (info['duration'] is num || info['formats'] is! List) {
      return info;
    }
    final length = await lengths.lengthOf(info);
    return {
      ...info,
      'duration': length.inMicroseconds / Duration.microsecondsPerSecond,
    };
  }
}

final linkedVideoReaderProvider = Provider<LinkedVideoReader>(
  (ref) => LinkedVideoReader(
    ref.watch(ytDlpProvider),
    lengths: ref.watch(streamLengthReaderProvider),
  ),
);
