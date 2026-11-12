import 'package:flutter/foundation.dart';

/// Where Make the clip is (spec FR-37), for the making view.
@immutable
sealed class MakingProgress {
  const MakingProgress();
}

/// Asking yt-dlp for fresh stream links.
class ReadingStreams extends MakingProgress {
  const ReadingStreams();
}

/// "Downloading cut 2 of 4", "3.1 MB of 7.8 MB · 1.2 MB/s".
class DownloadingCut extends MakingProgress {
  const DownloadingCut({
    required this.number,
    required this.count,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  /// From 1.
  final int number;
  final int count;
  final int receivedBytes;
  final int totalBytes;
  final double bytesPerSecond;

  double get fraction => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

/// Media3 joining the cuts.
class JoiningCuts extends MakingProgress {
  const JoiningCuts(this.fraction);

  final double fraction;
}

/// Fingerprinting and keeping the joined file (FR-1).
class KeepingClip extends MakingProgress {
  const KeepingClip();
}
