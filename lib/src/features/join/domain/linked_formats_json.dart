import 'dart:math' as math;

import 'package:status_studio/src/features/join/domain/stream_choice.dart';

const _bitsPerKilobit = 1000;

/// The streams in yt-dlp's `-J` JSON that can be fetched in byte ranges:
/// one file at a URL (HLS playlists and fragmented DASH can't). Adapted
/// from M7's `yt_dlp_info.dart` (removed in `a5294bf`).
LinkedFormats linkedFormatsFromYtDlpJson(Map<String, Object?> info) {
  final listed = info['formats'];
  final formats = [
    if (listed is List<Object?>)
      for (final format in listed)
        if (format is Map<String, Object?> && _isRangeFetchable(format)) format,
  ];
  return LinkedFormats(
    video: [
      for (final format in formats)
        if (_isVideoOnly(format)) _videoFormat(format),
    ],
    audio: _audioFormats(formats.where(_isAudioOnly).toList()),
    whole: [
      for (final format in formats)
        if (_carriesBoth(format)) _videoFormat(format),
    ],
  );
}

const _fileProtocols = {'https', 'http'};
const _dashProtocol = 'http_dash_segments';

/// Facebook and Instagram list each DASH stream as one file, with no
/// `fragments` list (spec FR-50).
bool _isRangeFetchable(Map<String, Object?> format) =>
    _isOneFile(format) &&
    format['url'] is String &&
    format['format_id'] is String;

bool _isOneFile(Map<String, Object?> format) {
  final protocol = format['protocol'];
  if (_fileProtocols.contains(protocol)) {
    return true;
  }
  return protocol == _dashProtocol && format['fragments'] == null;
}

/// Only text values: yt-dlp writes every header as text.
Map<String, String> _httpHeaders(Map<String, Object?> format) => {
  if (format['http_headers'] case final Map<Object?, Object?> headers)
    for (final MapEntry(:key, :value) in headers.entries)
      if (key is String && value is String) key: value,
};

bool _hasCodec(Object? codec) => codec is String && codec != 'none';

bool _isVideoOnly(Map<String, Object?> format) =>
    _hasCodec(format['vcodec']) && !_hasCodec(format['acodec']);

bool _isAudioOnly(Map<String, Object?> format) =>
    _hasCodec(format['acodec']) && !_hasCodec(format['vcodec']);

/// A codec yt-dlp leaves out is unknown, not missing: sites often don't
/// name the codecs of a file with both (*Claude's call*, FR-50).
bool _carriesBoth(Map<String, Object?> format) =>
    format['vcodec'] != 'none' && format['acodec'] != 'none';

StreamFormat _videoFormat(Map<String, Object?> format) => StreamFormat(
  formatId: format['format_id']! as String,
  url: Uri.parse(format['url']! as String),
  container: _container(format),
  codec: _textOr(format['vcodec'], ''),
  height: _shortSide(format),
  bitrate: _bitrate(format, 'vbr'),
  httpHeaders: _httpHeaders(format),
  sizeBytes: _sizeOf(format),
);

String _textOr(Object? value, String fallback) =>
    value is String ? value : fallback;

int? _sizeOf(Map<String, Object?> format) =>
    switch (format['filesize'] ?? format['filesize_approx']) {
      final num bytes => bytes.toInt(),
      _ => null,
    };

/// yt-dlp ranks the original track highest (dubs and descriptive audio
/// lower), so every track at the top rank counts as the default.
List<StreamFormat> _audioFormats(List<Map<String, Object?>> formats) {
  int preference(Map<String, Object?> format) =>
      (format['language_preference'] as num?)?.toInt() ?? -1;
  final top = formats.map(preference).fold(-1 << 31, math.max);
  return [
    for (final format in formats)
      StreamFormat(
        formatId: format['format_id']! as String,
        url: Uri.parse(format['url']! as String),
        container: _container(format),
        codec: '',
        height: 0,
        bitrate: _bitrate(format, 'abr'),
        isDefaultTrack: preference(format) == top,
        httpHeaders: _httpHeaders(format),
      ),
  ];
}

int _whole(Object? value) => value is num ? value.toInt() : 0;

/// A site may give the height and not the width; a missing side is 0.
int _shortSide(Map<String, Object?> format) {
  final sides = [
    _whole(format['width']),
    _whole(format['height']),
  ].where((side) => side > 0);
  return sides.isEmpty ? 0 : sides.reduce(math.min);
}

/// `m4a` is MP4 audio: both carry the segment index cuts need.
String _container(Map<String, Object?> format) {
  final extension = format['ext'];
  return extension == 'm4a' ? 'mp4' : '$extension';
}

/// yt-dlp gives kilobits per second; [StreamFormat] wants bits.
int _bitrate(Map<String, Object?> format, String key) {
  final kilobits = (format[key] ?? format['tbr']) as num? ?? 0;
  return (kilobits * _bitsPerKilobit).round();
}
