import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// A finished reel in the Recent list (spec §6.1, FR-11).
@immutable
class RecentReel {
  const RecentReel({
    required this.id,
    required this.title,
    required this.videoPath,
    required this.thumbnailPath,
    required this.duration,
    required this.size,
    required this.createdAt,
  });

  /// Throws [FormatException] or [TypeError] for a malformed entry.
  factory RecentReel.fromJson(Map<String, Object?> json) => RecentReel(
    id: json['id']! as String,
    title: json['title']! as String,
    videoPath: json['videoPath']! as String,
    thumbnailPath: json['thumbnailPath']! as String,
    duration: Duration(milliseconds: json['durationMs']! as int),
    size: OutputSize(json['width']! as int, json['height']! as int),
    createdAt: DateTime.parse(json['createdAt']! as String),
  );

  final String id;

  /// The caption's first line, shown in the list.
  final String title;
  final String videoPath;
  final String thumbnailPath;
  final Duration duration;

  /// The MP4's frame size, shown on Done.
  final OutputSize size;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'videoPath': videoPath,
    'thumbnailPath': thumbnailPath,
    'durationMs': duration.inMilliseconds,
    'width': size.width,
    'height': size.height,
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is RecentReel &&
      other.id == id &&
      other.title == title &&
      other.videoPath == videoPath &&
      other.thumbnailPath == thumbnailPath &&
      other.duration == duration &&
      other.size == size &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    videoPath,
    thumbnailPath,
    duration,
    size,
    createdAt,
  );
}
