import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/data/cut_downloader.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/data/recent_reels_repository.dart';
import 'package:status_studio/src/features/library/domain/video_history.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/source/application/video_thumbnail.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/topic/application/link_sessions_controller.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// What [VideoDeleter] deletes from; tests override each.
class VideoDeleterStores {
  const VideoDeleterStores({
    required this.scripts,
    required this.topics,
    required this.sources,
    required this.links,
    required this.cuts,
    required this.reels,
  });

  final Future<TranscriptStore> Function() scripts;
  final Future<TopicStore> Function() topics;
  final Future<SourceCache> Function() sources;
  final LinkedClipStore links;
  final CutDownloader cuts;
  final RecentReelsRepository reels;
}

/// Delete video on History (spec FR-44): the video's saved scripts (every
/// language, partial runs included, and kept fine-tunes with them), its
/// unfinished work, kept files, cut downloads and reels in the app. Copies
/// saved to the gallery stay.
class VideoDeleter {
  const VideoDeleter(this.stores, {required this.onDeleted});

  final VideoDeleterStores stores;

  /// Lets every list that showed the video read again.
  final VoidCallback onDeleted;

  Future<void> deleteVideo(VideoHistory video) async {
    switch (video.key) {
      case LinkedVideoKey(:final videoKey):
        await _deleteLinked(videoKey);
      case LocalVideoKey(:final videoId):
        await _deleteFingerprint(videoId);
    }
    for (final reel in video.reels) {
      await stores.reels.delete(reel.id);
    }
    onDeleted();
  }

  /// Every clip joined from it goes too, and the audio its script was
  /// written from (`v_yt_<ID>`).
  Future<void> _deleteLinked(String videoKey) async {
    for (final clipId in await _joinedClipsOf(videoKey)) {
      await _deleteFingerprint(clipId);
    }
    await _deleteFingerprint('v_yt_$videoKey');
    await (await stores.topics()).deleteVideo(videoKey);
    await stores.cuts.deleteCutsOf(videoKey);
  }

  Future<void> _deleteFingerprint(String videoId) async {
    await (await stores.scripts()).deleteVideo(videoId);
    await (await stores.sources()).deleteVideo(videoId);
  }

  Future<List<String>> _joinedClipsOf(String videoKey) async {
    final videoIds = await (await stores.sources()).videoIds();
    return [
      for (final videoId in videoIds)
        if ((await stores.links.read(videoId))?.videoKey == videoKey) videoId,
    ];
  }
}

final videoDeleterProvider = Provider<VideoDeleter>((ref) {
  return VideoDeleter(
    VideoDeleterStores(
      scripts: () => ref.read(transcriptStoreProvider.future),
      topics: () => ref.read(topicStoreProvider.future),
      sources: () => ref.read(sourceCacheProvider.future),
      links: ref.read(linkedClipStoreProvider),
      cuts: ref.read(cutDownloaderProvider),
      reels: ref.read(recentReelsRepositoryProvider),
    ),
    onDeleted: () {
      if (!ref.mounted) {
        return;
      }
      ref
        ..invalidate(recentReelsProvider)
        ..invalidate(savedScriptsProvider)
        ..invalidate(fineTuneDraftsProvider)
        ..invalidate(linkSessionsProvider)
        ..invalidate(isVideoKeptProvider)
        ..invalidate(linkedClipProvider)
        ..invalidate(videoThumbnailProvider);
    },
  );
});
