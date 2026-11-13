import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';

/// A stretch of a linked video downloaded as one MP4 (spec FR-37). Times
/// are in the linked video's time.
@immutable
class CutFile {
  const CutFile({
    required this.file,
    required this.streamsKey,
    required this.fileStart,
    required this.covered,
  });

  /// Throws [FormatException] for a JSON that isn't a saved cut.
  factory CutFile.fromJson(File file, Map<String, Object?> json) {
    if (json case {
      'streams': final String streamsKey,
      'fileStartMs': final int fileStartMs,
      'coveredStartMs': final int coveredStartMs,
      'coveredEndMs': final int coveredEndMs,
    }) {
      return CutFile(
        file: file,
        streamsKey: streamsKey,
        fileStart: Duration(milliseconds: fileStartMs),
        covered: ClipWindow(
          start: Duration(milliseconds: coveredStartMs),
          end: Duration(milliseconds: coveredEndMs),
        ),
      );
    }
    throw const FormatException('Not a saved cut.');
  }

  final File file;

  /// [CutStreams.key] of the streams it was made from.
  final String streamsKey;

  /// The video time at the file's time zero: the earlier of its two
  /// streams' first segment starts, which for the picture is a keyframe.
  final Duration fileStart;

  /// The stretch both picture and sound cover.
  final ClipWindow covered;

  /// Where video time [time] is in the file.
  Duration positionOf(Duration time) => time - fileStart;

  Map<String, Object?> toJson() => {
    'streams': streamsKey,
    'fileStartMs': fileStart.inMilliseconds,
    'coveredStartMs': covered.start.inMilliseconds,
    'coveredEndMs': covered.end.inMilliseconds,
  };
}
