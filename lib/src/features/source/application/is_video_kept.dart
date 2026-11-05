import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';

/// Whether the kept copy of [videoId] is still on the phone (spec FR-1).
/// Recent rows use it to ask for the video again when it is gone.
final isVideoKeptProvider = FutureProvider.family<bool, String>((
  ref,
  videoId,
) async {
  final cache = await ref.watch(sourceCacheProvider.future);
  return cache.keptLocalVideos(videoId).isNotEmpty;
});
