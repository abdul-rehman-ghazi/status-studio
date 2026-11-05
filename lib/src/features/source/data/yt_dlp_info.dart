import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/source/domain/stream_choice.dart';
import 'package:status_studio/src/features/transcript/domain/caption_track_choice.dart';

const _bitsPerKilobit = 1000;

/// yt-dlp marks YouTube's own speech recognition track with this suffix;
/// every other automatic track is a machine translation of it.
const _originalSuffix = '-orig';

/// One stream yt-dlp found that can be fetched in byte ranges.
@immutable
class YtDlpFormat {
  const YtDlpFormat({
    required this.url,
    required this.totalBytes,
    required this.choice,
  });

  final Uri url;
  final int totalBytes;

  /// Its `index` is the position in the list this format is in.
  final StreamChoice choice;
}

/// A caption track, with the URL of its `json3` version.
@immutable
class YtDlpCaptionTrack {
  const YtDlpCaptionTrack({required this.choice, required this.json3Url});

  /// Its `index` is the position in [YtDlpInfo.captionTracks].
  final CaptionTrackChoice choice;
  final Uri json3Url;
}

/// What the app uses from yt-dlp's `-J` JSON for one video.
@immutable
class YtDlpInfo {
  const YtDlpInfo({
    required this.video,
    required this.videoFormats,
    required this.audioFormats,
    required this.captionTracks,
  });

  /// Throws [VideoUnavailableException] for a live stream or a video
  /// without a length: neither can be downloaded.
  factory YtDlpInfo.fromJson(Map<String, Object?> json) {
    final seconds = json['duration'] as num?;
    if (json['is_live'] == true || seconds == null) {
      throw const VideoUnavailableException('Live or without a length.');
    }
    final formats = [
      for (final format in json['formats']! as List<Object?>)
        format! as Map<String, Object?>,
    ].where(_isRangeFetchable);
    return YtDlpInfo(
      video: SourceVideo(
        videoId: json['id']! as String,
        title: json['title']! as String,
        duration: Duration(milliseconds: (seconds * 1000).round()),
      ),
      videoFormats: _videoFormats(formats.where(_isVideoOnly).toList()),
      audioFormats: _audioFormats(formats.where(_isAudioOnly).toList()),
      captionTracks: _captionTracks(json),
    );
  }

  final SourceVideo video;
  final List<YtDlpFormat> videoFormats;
  final List<YtDlpFormat> audioFormats;
  final List<YtDlpCaptionTrack> captionTracks;
}

/// HLS playlists and formats without a size can't be fetched in ranges.
bool _isRangeFetchable(Map<String, Object?> format) =>
    format['protocol'] == 'https' &&
    format['url'] is String &&
    ((format['filesize'] as num?) ?? 0) > 0;

bool _hasCodec(Object? codec) => codec is String && codec != 'none';

bool _isVideoOnly(Map<String, Object?> format) =>
    _hasCodec(format['vcodec']) && !_hasCodec(format['acodec']);

bool _isAudioOnly(Map<String, Object?> format) =>
    _hasCodec(format['acodec']) && !_hasCodec(format['vcodec']);

List<YtDlpFormat> _videoFormats(List<Map<String, Object?>> formats) => [
  for (final (index, format) in formats.indexed)
    YtDlpFormat(
      url: Uri.parse(format['url']! as String),
      totalBytes: (format['filesize']! as num).toInt(),
      choice: StreamChoice(
        height: qualityHeight(
          width: (format['width'] as num?)?.toInt() ?? 0,
          height: (format['height'] as num?)?.toInt() ?? 0,
        ),
        container: _container(format),
        bitrate: _bitrate(format, 'vbr'),
        index: index,
        codec: format['vcodec']! as String,
      ),
    ),
];

/// yt-dlp ranks the original track highest (dubs and descriptive audio
/// lower), so every track at the top rank counts as the default.
List<YtDlpFormat> _audioFormats(List<Map<String, Object?>> formats) {
  int preference(Map<String, Object?> format) =>
      (format['language_preference'] as num?)?.toInt() ?? -1;
  final top = formats.map(preference).fold(-1 << 31, (a, b) => a > b ? a : b);
  return [
    for (final (index, format) in formats.indexed)
      YtDlpFormat(
        url: Uri.parse(format['url']! as String),
        totalBytes: (format['filesize']! as num).toInt(),
        choice: StreamChoice(
          height: 0,
          container: _container(format),
          bitrate: _bitrate(format, 'abr'),
          index: index,
          isDefaultTrack: preference(format) == top,
        ),
      ),
  ];
}

/// `m4a` is MP4 audio, and only MP4 has the segment index clips need.
String _container(Map<String, Object?> format) {
  final extension = format['ext']! as String;
  return extension == 'm4a' ? 'mp4' : extension;
}

/// yt-dlp gives kilobits per second; [StreamChoice] wants bits.
int _bitrate(Map<String, Object?> format, String key) {
  final kilobits = (format[key] ?? format['tbr']) as num? ?? 0;
  return (kilobits * _bitsPerKilobit).round();
}

List<YtDlpCaptionTrack> _captionTracks(Map<String, Object?> json) {
  final manual = _tracksIn(json['subtitles'])
      .where((track) => track.language != 'live_chat')
      .map((track) => (track: track, isAutoGenerated: false));
  final automatic = _tracksIn(json['automatic_captions'])
      .where((track) => track.language.endsWith(_originalSuffix))
      .map((track) => (track: track, isAutoGenerated: true));
  final usable = [
    ...manual,
    ...automatic,
  ].where((entry) => entry.track.json3Url != null).toList();
  return [
    for (final (index, entry) in usable.indexed)
      YtDlpCaptionTrack(
        choice: CaptionTrackChoice(
          languageCode: _withoutOriginalSuffix(entry.track.language),
          isAutoGenerated: entry.isAutoGenerated,
          index: index,
        ),
        json3Url: entry.track.json3Url!,
      ),
  ];
}

/// Each language in a yt-dlp caption map, with its `json3` URL if listed.
List<({String language, Uri? json3Url})> _tracksIn(Object? captions) {
  if (captions is! Map<String, Object?>) {
    return const [];
  }
  return [
    for (final MapEntry(key: language, value: formats) in captions.entries)
      (language: language, json3Url: _json3Url(formats)),
  ];
}

Uri? _json3Url(Object? formats) {
  if (formats is! List<Object?>) {
    return null;
  }
  final json3 = formats
      .whereType<Map<String, Object?>>()
      .where((format) => format['ext'] == 'json3' && format['url'] is String)
      .firstOrNull;
  return json3 == null ? null : Uri.parse(json3['url']! as String);
}

String _withoutOriginalSuffix(String language) =>
    language.endsWith(_originalSuffix)
    ? language.substring(0, language.length - _originalSuffix.length)
    : language;
