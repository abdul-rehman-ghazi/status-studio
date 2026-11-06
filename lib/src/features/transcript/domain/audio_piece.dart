import 'dart:io';

import 'package:flutter/foundation.dart';

/// One stretch of the video's audio that Groq transcribes on its own
/// (spec FR-12a).
@immutable
class AudioPiece {
  const AudioPiece({required this.file, required this.start});

  final File file;

  /// Where the piece begins in the video, as FFmpeg's segment list reports
  /// it: cuts fall on audio frames, so this is close to, not exactly, a
  /// multiple of the piece length.
  final Duration start;

  @override
  bool operator ==(Object other) =>
      other is AudioPiece &&
      other.file.path == file.path &&
      other.start == start;

  @override
  int get hashCode => Object.hash(file.path, start);
}
