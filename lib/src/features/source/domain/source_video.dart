import 'package:flutter/foundation.dart';

/// [videoId] is the file's fingerprint, `v_<16 hex>` (spec FR-1); [title] is
/// the file's name without its extension.
@immutable
class SourceVideo {
  const SourceVideo({
    required this.videoId,
    required this.title,
    required this.duration,
  });

  /// Throws [FormatException] when [json] isn't a saved video. A `channel`
  /// key left by an older version is ignored.
  factory SourceVideo.fromJson(Map<String, Object?> json) {
    if (json case {
      'videoId': final String videoId,
      'title': final String title,
      'durationMs': final int durationMs,
    }) {
      return SourceVideo(
        videoId: videoId,
        title: title,
        duration: Duration(milliseconds: durationMs),
      );
    }
    throw const FormatException('Not a saved video.');
  }

  final String videoId;
  final String title;
  final Duration duration;

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'title': title,
    'durationMs': duration.inMilliseconds,
  };

  SourceVideo copyWith({String? videoId, String? title, Duration? duration}) {
    return SourceVideo(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceVideo &&
      other.videoId == videoId &&
      other.title == title &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(videoId, title, duration);
}
