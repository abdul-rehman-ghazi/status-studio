/// yt-dlp `-J` JSON for tests, hand-written: real output carries the
/// requester's IP address in every URL.
library;

/// Where every format and caption URL points; tests serving files set it
/// to their loopback server.
var mediaBase = 'https://media.example';

Map<String, Object?> audioFormat(
  String id, {
  required String ext,
  required double abr,
  int languagePreference = -1,
  int filesize = 3342572,
}) => {
  'format_id': id,
  'ext': ext,
  'acodec': ext == 'm4a' ? 'mp4a.40.5' : 'opus',
  'vcodec': 'none',
  'abr': abr,
  'tbr': abr,
  'protocol': 'https',
  'filesize': filesize,
  'language_preference': languagePreference,
  'url': '$mediaBase/audio/$id',
};

Map<String, Object?> videoFormat(
  String id, {
  required int height,
  String protocol = 'https',
  int? filesize = 21229386,
}) => {
  'format_id': id,
  'ext': 'mp4',
  'acodec': 'none',
  'vcodec': 'avc1.4d401e',
  'width': height * 16 ~/ 9,
  'height': height,
  'tbr': 310.5,
  'protocol': protocol,
  'filesize': filesize,
  'url': '$mediaBase/video/$id',
};

Map<String, Object?> captionFormats(String lang) => {
  'formats': [
    {'ext': 'srv3', 'url': '$mediaBase/captions/$lang.srv3'},
    {'ext': 'json3', 'url': '$mediaBase/captions/$lang.json3'},
  ],
};

Map<String, Object?> videoJson({
  Object? duration = 548,
  bool isLive = false,
  List<Map<String, Object?>>? formats,
  Map<String, Object?> subtitles = const {},
  Map<String, Object?> automaticCaptions = const {},
}) => {
  'id': 's6kE_uP3xH4',
  'title': 'Main Madine Chala',
  'channel': 'Heera Gold',
  'uploader': 'Heera Gold uploads',
  'duration': duration,
  'is_live': isLive,
  'formats':
      formats ??
      [
        audioFormat('139', ext: 'm4a', abr: 48.8),
        audioFormat('251', ext: 'webm', abr: 140),
        videoFormat('134', height: 360),
      ],
  'subtitles': {
    for (final MapEntry(:key, :value) in subtitles.entries)
      key: (value as Map<String, Object?>)['formats'],
  },
  'automatic_captions': {
    for (final MapEntry(:key, :value) in automaticCaptions.entries)
      key: (value as Map<String, Object?>)['formats'],
  },
};
