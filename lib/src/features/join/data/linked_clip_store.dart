import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/domain/linked_clip.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';

/// `sources/<videoId>/link.json` (spec FR-37). It lives in the video's own
/// folder, so it goes when the video is pruned (FR-14).
class LinkedClipStore {
  const LinkedClipStore(this.sources);

  final Future<SourceCache> sources;

  Future<void> save(String videoId, LinkedClip clip) async {
    final file = (await sources).linkFile(videoId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(clip.toJson()));
  }

  /// Null for a video that wasn't joined from a link, or whose file can't
  /// be read: it is then treated as any local video.
  Future<LinkedClip?> read(String videoId) async {
    final file = (await sources).linkFile(videoId);
    if (!await file.exists()) {
      return null;
    }
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? LinkedClip.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }
}

final linkedClipStoreProvider = Provider<LinkedClipStore>(
  (ref) => LinkedClipStore(ref.watch(sourceCacheProvider.future)),
);

/// The linked clip behind [videoId], if it is one.
final linkedClipProvider = FutureProvider.family<LinkedClip?, String>(
  (ref, videoId) => ref.watch(linkedClipStoreProvider).read(videoId),
);
