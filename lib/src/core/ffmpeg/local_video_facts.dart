import 'dart:convert';

import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// What the app needs to know about a video file before using it (spec §5).
class LocalVideoFacts {
  const LocalVideoFacts({
    required this.duration,
    required this.sizeBytes,
    required this.rotationDegrees,
    required this.storedWidth,
    required this.storedHeight,
    required this.hasAudio,
    required this.videoCodec,
    required this.pictureStart,
  });

  final Duration duration;
  final int sizeBytes;

  /// Clockwise turn a player applies for display: 0, 90, 180 or 270.
  final int rotationDegrees;
  final int storedWidth;
  final int storedHeight;
  final bool hasAudio;

  /// ffprobe's `codec_name` of the video stream, such as `h264` or `av1`.
  final String videoCodec;

  /// When the first picture comes, rounded up to a tenth of a second. A video
  /// trimmed elsewhere can keep its sound from zero but start its picture
  /// later; players and the renderer can't start before the picture (M41).
  final Duration pictureStart;

  /// The bundled FFmpeg has no AV1 decoder (no dav1d, no MediaCodec), so it
  /// can't sample frames or make thumbnails of an AV1 video; such a video is
  /// kept as an H.264 copy instead (spec FR-1, M31).
  bool get needsH264Copy => videoCodec == 'av1';

  bool get _isTurnedSideways => rotationDegrees == 90 || rotationDegrees == 270;

  int get displayedWidth => _isTurnedSideways ? storedHeight : storedWidth;

  int get displayedHeight => _isTurnedSideways ? storedWidth : storedHeight;

  /// Without audio there is nothing to write a script from (spec §8).
  LocalVideoFacts requireAudio() {
    if (!hasAudio) {
      throw const VideoUnreadableException('The video has no audio track');
    }
    return this;
  }
}

List<String> localVideoProbeArguments(String path) => [
  '-v',
  'error',
  '-show_streams',
  '-show_format',
  '-of',
  'json',
  path,
];

/// Reads ffprobe's `-show_streams -show_format -of json` output.
/// Throws [VideoUnreadableException] when it holds no usable video.
LocalVideoFacts parseLocalVideoFacts(String probeJson) {
  final root = _decodeObject(jsonObjectIn(probeJson));
  final streams = _objectsIn(root['streams']);
  final video = _firstVideoStream(streams);
  if (video == null) {
    throw const VideoUnreadableException('No video stream');
  }
  final format = _asObject(root['format']);
  return LocalVideoFacts(
    duration: _durationOf(format, video),
    sizeBytes: _positiveWhole(format['size'], 'file size'),
    rotationDegrees: _rotationOf(video),
    storedWidth: _positiveWhole(video['width'], 'video width'),
    storedHeight: _positiveWhole(video['height'], 'video height'),
    hasAudio: _firstStreamOfType(streams, 'audio') != null,
    videoCodec: video['codec_name'] is String
        ? video['codec_name']! as String
        : '',
    pictureStart: _pictureStartOf(format, video),
  );
}

/// The video stream's start against the file's own, so a file whose times
/// don't begin at zero isn't mistaken for a late picture.
Duration _pictureStartOf(
  Map<String, Object?> format,
  Map<String, Object?> videoStream,
) {
  final streamSeconds = _decimalNumber(videoStream['start_time']) ?? 0;
  final fileSeconds = _decimalNumber(format['start_time']) ?? 0;
  final lateMilliseconds = ((streamSeconds - fileSeconds) * 1000).round();
  if (lateMilliseconds <= 0) {
    return Duration.zero;
  }
  // Whole milliseconds first: 0.3 s times ten is a hair over 3 in floating
  // point and would round up to 0.4 s.
  return Duration(milliseconds: (lateMilliseconds + 99) ~/ 100 * 100);
}

/// FFmpeg Kit's output holds every log line, so stray ffprobe messages can
/// surround the JSON. Throws [VideoUnreadableException] when there is no
/// object in [output].
String jsonObjectIn(String output) {
  final objectStart = output.indexOf('{');
  final objectEnd = output.lastIndexOf('}');
  if (objectStart < 0 || objectEnd < objectStart) {
    throw const VideoUnreadableException('ffprobe output has no JSON object');
  }
  return output.substring(objectStart, objectEnd + 1);
}

Map<String, Object?> _decodeObject(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
  } on FormatException {
    throw const VideoUnreadableException('ffprobe output is not JSON');
  }
  throw const VideoUnreadableException('ffprobe output is not an object');
}

Map<String, Object?> _asObject(Object? value) =>
    value is Map<String, Object?> ? value : const {};

List<Map<String, Object?>> _objectsIn(Object? value) =>
    value is List ? value.whereType<Map<String, Object?>>().toList() : const [];

Map<String, Object?>? _firstStreamOfType(
  List<Map<String, Object?>> streams,
  String codecType,
) {
  for (final stream in streams) {
    if (stream['codec_type'] == codecType) {
      return stream;
    }
  }
  return null;
}

/// Cover art in an audio file is listed as a video stream; it isn't a video.
Map<String, Object?>? _firstVideoStream(List<Map<String, Object?>> streams) {
  for (final stream in streams) {
    if (stream['codec_type'] == 'video' && !_isCoverArt(stream)) {
      return stream;
    }
  }
  return null;
}

bool _isCoverArt(Map<String, Object?> stream) =>
    _wholeNumber(_asObject(stream['disposition'])['attached_pic']) == 1;

Duration _durationOf(
  Map<String, Object?> format,
  Map<String, Object?> videoStream,
) {
  final seconds =
      _positiveDecimal(format['duration']) ??
      _positiveDecimal(videoStream['duration']);
  if (seconds == null) {
    throw const VideoUnreadableException('The video has no duration');
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

double? _positiveDecimal(Object? value) {
  final number = _decimalNumber(value);
  return number != null && number > 0 ? number : null;
}

int _positiveWhole(Object? value, String fact) {
  final number = _wholeNumber(value);
  if (number == null || number <= 0) {
    throw VideoUnreadableException('ffprobe gave no $fact');
  }
  return number;
}

/// Newer ffprobe puts the turn in the display matrix side data, as a
/// counter-clockwise angle; older files carry a clockwise `rotate` tag.
int _rotationOf(Map<String, Object?> videoStream) {
  final sideDataAngle = _sideDataRotation(videoStream);
  if (sideDataAngle != null) {
    return _quarterTurnOrNone(-sideDataAngle);
  }
  final tags = _asObject(videoStream['tags']);
  return _quarterTurnOrNone(_decimalNumber(tags['rotate']) ?? 0);
}

double? _sideDataRotation(Map<String, Object?> videoStream) {
  for (final sideData in _objectsIn(videoStream['side_data_list'])) {
    final angle = _decimalNumber(sideData['rotation']);
    if (angle != null) {
      return angle;
    }
  }
  return null;
}

int _quarterTurnOrNone(double clockwiseDegrees) {
  final normalized = clockwiseDegrees.round() % 360;
  return normalized % 90 == 0 ? normalized : 0;
}

double? _decimalNumber(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text),
  _ => null,
};

int? _wholeNumber(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};
