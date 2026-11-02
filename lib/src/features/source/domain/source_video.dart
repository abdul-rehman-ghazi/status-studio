import 'package:flutter/foundation.dart';

@immutable
class SourceVideo {
  const SourceVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
  });

  /// Throws [FormatException] when [json] isn't a saved video.
  factory SourceVideo.fromJson(Map<String, Object?> json) {
    if (json case {
      'videoId': final String videoId,
      'title': final String title,
      'channel': final String channel,
      'durationMs': final int durationMs,
    }) {
      return SourceVideo(
        videoId: videoId,
        title: title,
        channel: channel,
        duration: Duration(milliseconds: durationMs),
      );
    }
    throw const FormatException('Not a saved video.');
  }

  final String videoId;
  final String title;
  final String channel;
  final Duration duration;

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'title': title,
    'channel': channel,
    'durationMs': duration.inMilliseconds,
  };

  SourceVideo copyWith({
    String? videoId,
    String? title,
    String? channel,
    Duration? duration,
  }) {
    return SourceVideo(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      channel: channel ?? this.channel,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceVideo &&
      other.videoId == videoId &&
      other.title == title &&
      other.channel == channel &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(videoId, title, channel, duration);
}
