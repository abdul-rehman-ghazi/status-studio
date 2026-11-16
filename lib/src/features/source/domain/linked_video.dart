import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/video_link.dart';
import 'package:status_studio/src/features/transcript/domain/youtube_captions.dart';

/// yt-dlp's `extractor_key` for YouTube; links kept before M70 have no site
/// and are YouTube (spec FR-50).
const youTubeSite = 'Youtube';

const _maxKeyLength = 64;
final _unsafeKeyCharacters = RegExp(r'[^A-Za-z0-9_-]');

/// The key that names a linked video's folders and records (spec FR-50):
/// YouTube's ID as before M70, else `<site>_<id>` made safe for a file
/// name, with a long ID replaced by the start of its SHA-256.
String videoKeyFor(String site, String id) {
  if (site == youTubeSite) {
    return id;
  }
  final sitePrefix = '${site.toLowerCase()}_'.replaceAll(
    _unsafeKeyCharacters,
    '_',
  );
  final key = '$sitePrefix$id'.replaceAll(_unsafeKeyCharacters, '_');
  if (key.length <= _maxKeyLength) {
    return key;
  }
  return '$sitePrefix${sha256.convert(utf8.encode(id)).toString().substring(0, 16)}';
}

/// What the link card shows about a linked video (spec FR-35, FR-50), read
/// from yt-dlp's `-J` JSON.
class LinkedVideo {
  const LinkedVideo({
    required this.videoKey,
    required this.pageUrl,
    required this.site,
    required this.title,
    required this.channel,
    required this.duration,
    required this.thumbnailUrl,
    required this.captionsUrl,
    required this.captionsLanguage,
  });

  /// Throws [SiteChangedException] when the JSON lacks the ID, the title or
  /// the length, or lists no formats: yt-dlp read the page but not the
  /// video. [pastedPageUrl] is the page when yt-dlp names none.
  factory LinkedVideo.fromYtDlpJson(
    Map<String, Object?> info, {
    required String pastedPageUrl,
  }) {
    final id = _textOrNull(info['id']);
    final title = info['title'];
    final durationSeconds = info['duration'];
    final formats = info['formats'];
    if (id == null || title is! String || durationSeconds is! num) {
      throw const SiteChangedException('yt-dlp gave no ID, title or length.');
    }
    if (formats is! List || formats.isEmpty) {
      throw const SiteChangedException('yt-dlp found no formats.');
    }
    final site = _textOrNull(info['extractor_key']) ?? youTubeSite;
    // Only YouTube's json3 tracks are read (FR-50); other sites' scripts
    // come from Groq.
    final captions = site == youTubeSite ? pickTopicCaptions(info) : null;
    return LinkedVideo(
      videoKey: videoKeyFor(site, id),
      pageUrl: _textOrNull(info['webpage_url']) ?? pastedPageUrl,
      site: site,
      title: title,
      channel: _channelOf(info),
      duration: Duration(milliseconds: (durationSeconds * 1000).round()),
      thumbnailUrl: _textOrNull(info['thumbnail']),
      captionsUrl: captions?.url,
      captionsLanguage: captions?.languageCode,
    );
  }

  /// Throws [FormatException] for a JSON that isn't a kept linked video
  /// (spec FR-38, FR-43).
  factory LinkedVideo.fromJson(Map<String, Object?> json) => switch (json) {
    {
      'id': final String id,
      'title': final String title,
      'channel': final String channel,
      'durationMs': final int durationMs,
      'thumbnailUrl': final String? thumbnailUrl,
      'captionsUrl': final String? captionsUrl,
    } =>
      LinkedVideo(
        videoKey: id,
        // Links kept before M70 have neither: they are YouTube.
        pageUrl: json['pageUrl'] as String? ?? youTubeWatchUrl(id),
        site: json['site'] as String? ?? youTubeSite,
        title: title,
        channel: channel,
        duration: Duration(milliseconds: durationMs),
        thumbnailUrl: thumbnailUrl,
        captionsUrl: captionsUrl,
        // Links kept before M50 have none: their captions aren't read.
        captionsLanguage: json['captionsLanguage'] as String?,
      ),
    _ => throw const FormatException('Not a linked video.'),
  };

  /// Names the video's folders and records; see [videoKeyFor].
  final String videoKey;

  /// The page yt-dlp reads the video from.
  final String pageUrl;

  /// yt-dlp's name for the site, e.g. `Facebook`, `Instagram`, `Youtube`.
  final String site;
  final String title;

  /// Empty when yt-dlp names neither a channel nor an uploader.
  final String channel;
  final Duration duration;

  /// Null when the site offers no thumbnail; the card then shows its icon.
  final String? thumbnailUrl;

  /// The caption track the topic search may read (FR-36); null when Groq
  /// must write the script.
  final String? captionsUrl;

  /// The track's language code, e.g. `hi`; captions are read only when it
  /// is the output language (M50). Null when there is no track, or for a
  /// link kept before M50.
  final String? captionsLanguage;

  bool get isYouTube => site == youTubeSite;

  Map<String, Object?> toJson() => {
    'id': videoKey,
    'pageUrl': pageUrl,
    'site': site,
    'title': title,
    'channel': channel,
    'durationMs': duration.inMilliseconds,
    'thumbnailUrl': thumbnailUrl,
    'captionsUrl': captionsUrl,
    'captionsLanguage': captionsLanguage,
  };
}

String _channelOf(Map<String, Object?> info) =>
    _textOrNull(info['channel']) ?? _textOrNull(info['uploader']) ?? '';

String? _textOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
