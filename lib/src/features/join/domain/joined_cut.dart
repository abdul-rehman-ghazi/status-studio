import 'package:flutter/foundation.dart';

/// Where one cut of a joined clip came from in the YouTube video and where
/// it starts in the joined file, without the transition's margins (spec
/// FR-44): a reel's ranges are mapped back through it.
@immutable
class JoinedCut {
  const JoinedCut({
    required this.sourceStart,
    required this.sourceEnd,
    required this.joinedStart,
  });

  /// Throws [FormatException] for a JSON that isn't a joined cut.
  factory JoinedCut.fromJson(Object? json) => switch (json) {
    {
      'sourceStartMs': final int sourceStartMs,
      'sourceEndMs': final int sourceEndMs,
      'joinedStartMs': final int joinedStartMs,
    } =>
      JoinedCut(
        sourceStart: Duration(milliseconds: sourceStartMs),
        sourceEnd: Duration(milliseconds: sourceEndMs),
        joinedStart: Duration(milliseconds: joinedStartMs),
      ),
    _ => throw const FormatException('Not a joined cut.'),
  };

  final Duration sourceStart;
  final Duration sourceEnd;
  final Duration joinedStart;

  Duration get length => sourceEnd - sourceStart;

  Duration get joinedEnd => joinedStart + length;

  Map<String, Object?> toJson() => {
    'sourceStartMs': sourceStart.inMilliseconds,
    'sourceEndMs': sourceEnd.inMilliseconds,
    'joinedStartMs': joinedStart.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is JoinedCut &&
      other.sourceStart == sourceStart &&
      other.sourceEnd == sourceEnd &&
      other.joinedStart == joinedStart;

  @override
  int get hashCode => Object.hash(sourceStart, sourceEnd, joinedStart);
}
