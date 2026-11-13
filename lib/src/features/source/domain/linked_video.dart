import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/youtube_captions.dart';

/// What the link card shows about a linked video (spec FR-35), read from
/// yt-dlp's `-J` JSON.
class LinkedVideo {
  const LinkedVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnailUrl,
    required this.captionsUrl,
    required this.captionsLanguage,
  });

  /// Throws [YouTubeChangedException] when the JSON lacks the title or the
  /// length, or lists no formats: yt-dlp read the page but not the video.
  factory LinkedVideo.fromYtDlpJson(Map<String, Object?> info) {
    final title = info['title'];
    final durationSeconds = info['duration'];
    final formats = info['formats'];
    if (title is! String || durationSeconds is! num) {
      throw const YouTubeChangedException('yt-dlp gave no title or length.');
    }
    if (formats is! List || formats.isEmpty) {
      throw const YouTubeChangedException('yt-dlp found no formats.');
    }
    final captions = pickTopicCaptions(info);
    return LinkedVideo(
      videoId: '${info['id']}',
      title: title,
      channel: _channelOf(info),
      duration: Duration(milliseconds: (durationSeconds * 1000).round()),
      thumbnailUrl: _textOrNull(info['thumbnail']),
      captionsUrl: captions?.url,
      captionsLanguage: captions?.languageCode,
    );
  }

  /// YouTube's 11-character ID.
  final String videoId;
  final String title;

  /// Empty when yt-dlp names neither a channel nor an uploader.
  final String channel;
  final Duration duration;

  /// Null when YouTube offers no thumbnail; the card then shows its icon.
  final String? thumbnailUrl;

  /// The caption track the topic search may read (FR-36); null when Groq
  /// must write the script.
  final String? captionsUrl;

  /// The track's language code, e.g. `hi`; captions are read only when it
  /// is the output language (M50). Null when there is no track, or for a
  /// link kept before M50.
  final String? captionsLanguage;
}

String _channelOf(Map<String, Object?> info) =>
    _textOrNull(info['channel']) ?? _textOrNull(info['uploader']) ?? '';

String? _textOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
