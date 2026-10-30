import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';

/// A downloaded piece of the video covering [window] (FR-15).
@immutable
class ClipSource {
  const ClipSource({
    required this.file,
    required this.offset,
    required this.window,
  });

  final File file;

  /// The video time at which [file]'s own time zero falls; subtract it to
  /// seek inside the file.
  final Duration offset;
  final ClipWindow window;

  @override
  bool operator ==(Object other) =>
      other is ClipSource &&
      other.file.path == file.path &&
      other.offset == offset &&
      other.window == window;

  @override
  int get hashCode => Object.hash(file.path, offset, window);
}
