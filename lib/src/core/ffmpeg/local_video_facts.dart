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
  });

  final Duration duration;
  final int sizeBytes;

  /// Clockwise turn a player applies for display: 0, 90, 180 or 270.
  final int rotationDegrees;
  final int storedWidth;
  final int storedHeight;
  final bool hasAudio;

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
  );
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
