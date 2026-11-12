import 'package:flutter/foundation.dart';

/// A video the user brought in (spec FR-1): its ID is the file fingerprint
/// (`v_<16 hex>`) and its title the file name.
@immutable
class SourceVideo {
  const SourceVideo({
    required this.videoId,
    required this.title,
    required this.duration,
    this.pictureStart = Duration.zero,
  });

  /// Throws [FormatException] when [json] isn't a saved video. A `channel`
  /// key left by an older version is ignored, and a video saved before M41
  /// has no picture start, so it reads as zero.
  factory SourceVideo.fromJson(Map<String, Object?> json) {
    if (json case {
      'videoId': final String videoId,
      'title': final String title,
      'durationMs': final int durationMs,
    }) {
      final pictureStartMs = json['pictureStartMs'];
      return SourceVideo(
        videoId: videoId,
        title: title,
        duration: Duration(milliseconds: durationMs),
        pictureStart: Duration(
          milliseconds: pictureStartMs is int ? pictureStartMs : 0,
        ),
      );
    }
    throw const FormatException('Not a saved video.');
  }

  final String videoId;
  final String title;
  final Duration duration;

  /// The earliest a clip can start: where the picture begins, rounded up to
  /// a tenth of a second (spec FR-5, M41).
  final Duration pictureStart;

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'title': title,
    'durationMs': duration.inMilliseconds,
    'pictureStartMs': pictureStart.inMilliseconds,
  };

  SourceVideo copyWith({
    String? videoId,
    String? title,
    Duration? duration,
    Duration? pictureStart,
  }) {
    return SourceVideo(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      duration: duration ?? this.duration,
      pictureStart: pictureStart ?? this.pictureStart,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceVideo &&
      other.videoId == videoId &&
      other.title == title &&
      other.duration == duration &&
      other.pictureStart == pictureStart;

  @override
  int get hashCode => Object.hash(videoId, title, duration, pictureStart);
}
