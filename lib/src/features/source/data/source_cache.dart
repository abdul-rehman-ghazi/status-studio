import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Downloaded sources under `sources/<videoId>/` (spec §4 Storage).
///
/// Files are written as `<name>.part` and renamed only once complete, so a
/// file at its final path is always whole.
class SourceCache {
  SourceCache(this.root);

  final Directory root;

  File audioFile(String videoId, String extension) =>
      File('${_folder(videoId)}/audio.$extension');

  /// The video-only stream, in whatever container YouTube served.
  File videoFile(String videoId) => File('${_folder(videoId)}/video');

  /// Video and audio muxed together, for preview and rendering.
  File sourceFile(String videoId) => File('${_folder(videoId)}/source.mp4');

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
    try {
      var received = 0;
      await for (final chunk in bytes) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(_fraction(received, totalBytes));
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      await part.delete();
      rethrow;
    }
    final complete = await part.rename(target.path);
    onProgress(1);
    return complete;
  }

  String _folder(String videoId) => '${root.path}/$videoId';
}

double _fraction(int received, int total) =>
    total <= 0 ? 0 : math.min(1, received / total);

final sourceCacheProvider = FutureProvider<SourceCache>((ref) async {
  final temporary = await getTemporaryDirectory();
  return SourceCache(Directory('${temporary.path}/sources'));
});
