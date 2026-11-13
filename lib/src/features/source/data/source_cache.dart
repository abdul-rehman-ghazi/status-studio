import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// The videos the user brought in, under `sources/<videoId>/` (spec §4
/// Storage).
///
/// Files are written as `<name>.part` and renamed only once complete, so a
/// file at its final path is always whole.
class SourceCache {
  SourceCache(this.root);

  final Directory root;

  /// The video the user brought in, kept whole (spec FR-1).
  File localVideoFile(String videoId, String extension) =>
      File('${_folder(videoId)}/source.$extension');

  /// The H.264 copy kept in place of an AV1 video (spec FR-1, M31).
  File convertedVideoFile(String videoId) =>
      File('${_folder(videoId)}/source.h264.mp4');

  /// Where a conversion writes until it finishes; never a kept video.
  File convertingVideoFile(String videoId) =>
      File('${_folder(videoId)}/converting.mp4');

  /// The picture on the Source card for [videoId]'s kept video.
  File thumbnailFile(String videoId) =>
      File('${_folder(videoId)}/thumbnail.jpg');

  /// Where a clip joined from a link keeps its link, topic and join times
  /// (spec FR-37).
  File linkFile(String videoId) => File('${_folder(videoId)}/link.json');

  /// The fingerprints with a folder here.
  Future<List<String>> videoIds() async {
    if (!await root.exists()) {
      return const [];
    }
    return [
      await for (final folder in root.list())
        if (folder is Directory) folder.path.split('/').last,
    ];
  }

  /// Deletes everything kept for [videoId]: its video, thumbnail and
  /// `link.json` (spec FR-43, FR-44).
  Future<void> deleteVideo(String videoId) async {
    final folder = Directory(_folder(videoId));
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  }

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

final _keptVideoName = RegExp(r'^source(\.h264)?\.[A-Za-z0-9]+$');

double _fraction(int received, int total) =>
    total <= 0 ? 0 : math.min(1, received / total);

final sourceCacheProvider = FutureProvider<SourceCache>((ref) async {
  // Kept videos must outlive the system clearing the cache (spec §4).
  final support = await getApplicationSupportDirectory();
  return SourceCache(Directory('${support.path}/sources'));
});
