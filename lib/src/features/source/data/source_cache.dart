import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Downloaded sources under `sources/<videoId>/` (spec §4 Storage).
///
/// Files are written as `<name>.part` and renamed only once complete, so a
/// file at its final path is always whole.
class SourceCache {
  SourceCache(this.root);

  final Directory root;

  /// Low-bitrate audio for transcription.
  File scriptAudioFile(String videoId, String extension) =>
      File('${_folder(videoId)}/script_audio.$extension');

  /// Full-quality audio for the whole-video fallback source.
  File fullAudioFile(String videoId, String extension) =>
      File('${_folder(videoId)}/full_audio.$extension');

  /// The video-only stream, in whatever container YouTube served.
  File videoFile(String videoId) => File('${_folder(videoId)}/video');

  /// Video and audio muxed together, for preview and rendering.
  File sourceFile(String videoId) => File('${_folder(videoId)}/source.mp4');

  /// The video the user brought in, kept whole (spec FR-1).
  File localVideoFile(String videoId, String extension) =>
      File('${_folder(videoId)}/source.$extension');

  /// The videos already kept for [videoId], whatever their extension.
  List<File> keptLocalVideos(String videoId) {
    final folder = Directory(_folder(videoId));
    if (!folder.existsSync()) {
      return const [];
    }
    return folder
        .listSync()
        .whereType<File>()
        .where((file) => _keptVideoName.hasMatch(file.uri.pathSegments.last))
        .toList();
  }

  /// A muxed clip window. The name carries the window and the offset, so
  /// [cachedClips] can find it again after a restart.
  File clipFile(
    String videoId, {
    required ClipWindow window,
    required Duration offset,
  }) {
    return File(
      '${_folder(videoId)}/clip_${window.start.inMilliseconds}_'
      '${window.end.inMilliseconds}_${offset.inMilliseconds}.mp4',
    );
  }

  /// One stream of a clip window before muxing. Named per window, so two
  /// windows being fetched can never write into each other's file.
  File windowStreamFile(String videoId, ClipWindow window, String stream) =>
      File(
        '${_folder(videoId)}/window_${window.start.inMilliseconds}_'
        '${window.end.inMilliseconds}_$stream.mp4',
      );

  /// The complete clip windows already downloaded for [videoId].
  List<ClipSource> cachedClips(String videoId) {
    final folder = Directory(_folder(videoId));
    if (!folder.existsSync()) {
      return const [];
    }
    return folder
        .listSync()
        .whereType<File>()
        .map(_clipFromName)
        .nonNulls
        .toList();
  }

  bool isComplete(File target) => target.existsSync();

  Future<File> write(
    File target,
    Stream<List<int>> bytes, {
    required int totalBytes,
    required void Function(double fraction) onProgress,
  }) async {
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    // Reported before the first byte, so a download that never starts
    // shows as stuck at 0 instead of showing nothing.
    onProgress(0);
    try {
      var received = 0;
      await for (final chunk in bytes) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(_fraction(received, totalBytes));
      }
      await sink.close();
      _checkComplete(received, totalBytes);
    } catch (_) {
      await _discard(part, sink);
      rethrow;
    }
    final complete = await part.rename(target.path);
    onProgress(1);
    return complete;
  }

  String _folder(String videoId) => '${root.path}/$videoId';
}

/// Closes [sink] and deletes [part]. The sink may have failed to close
/// already, and its second close then rethrows; that must not leave the
/// partial file behind or hide the original failure.
Future<void> _discard(File part, IOSink sink) async {
  try {
    await sink.close();
  } on Exception {
    // The first failure is the one to report.
  }
  if (await part.exists()) {
    await part.delete();
  }
}

/// A stream can end quietly when its connection closes, so the byte count
/// is the only proof the download finished.
void _checkComplete(int received, int totalBytes) {
  if (totalBytes > 0 && received != totalBytes) {
    throw IncompleteDownloadException(
      'Received $received of $totalBytes bytes.',
    );
  }
}

final _keptVideoName = RegExp(r'^source\.[A-Za-z0-9]+$');

final _clipName = RegExp(r'clip_(\d+)_(\d+)_(\d+)\.mp4$');

/// The clip window [file] holds, if its name is a clip file's name.
ClipSource? _clipFromName(File file) {
  final match = _clipName.firstMatch(file.path);
  if (match == null) {
    return null;
  }
  Duration millis(int group) =>
      Duration(milliseconds: int.parse(match.group(group)!));
  return ClipSource(
    file: file,
    offset: millis(3),
    window: ClipWindow(start: millis(1), end: millis(2)),
  );
}

double _fraction(int received, int total) =>
    total <= 0 ? 0 : math.min(1, received / total);

final sourceCacheProvider = FutureProvider<SourceCache>((ref) async {
  // Kept videos must outlive the system clearing the cache (spec §4).
  final support = await getApplicationSupportDirectory();
  return SourceCache(Directory('${support.path}/sources'));
});
