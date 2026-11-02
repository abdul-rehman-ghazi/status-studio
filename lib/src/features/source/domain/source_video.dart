import 'package:flutter/foundation.dart';

@immutable
class SourceVideo {
  const SourceVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration duration;

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
