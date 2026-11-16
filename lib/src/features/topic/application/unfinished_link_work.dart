import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/data/fine_tune_draft_store.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/topic/application/link_sessions_controller.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';

/// A linked video's unfinished work (spec FR-43): its Review cuts session
/// and the joined clips of it whose fine-tune is kept. Starting new clips
/// from the video deletes all of it.
@immutable
class UnfinishedLinkWork {
  const UnfinishedLinkWork({
    required this.videoKey,
    required this.session,
    required this.joinedClipIds,
  });

  final String videoKey;
  final LinkSession? session;

  /// The fingerprints of the joined clips, each kept in `sources/<id>/`.
  final List<String> joinedClipIds;

  bool get isEmpty => session == null && joinedClipIds.isEmpty;
}

/// What [UnfinishedLinkWorks] reads and deletes; tests override each.
class UnfinishedLinkWorkStores {
  const UnfinishedLinkWorkStores({
    required this.topics,
    required this.drafts,
    required this.links,
    required this.sources,
  });

  final Future<TopicStore> Function() topics;
  final Future<FineTuneDraftStore> Function() drafts;
  final LinkedClipStore links;
  final Future<SourceCache> Function() sources;
}

/// Finds and deletes a linked video's unfinished work (spec FR-43, FR-44):
/// one unfinished piece per linked video.
class UnfinishedLinkWorks {
  const UnfinishedLinkWorks(this.stores, {required this.onDeleted});

  final UnfinishedLinkWorkStores stores;

  /// Lets the lists that show unfinished work read again.
  final VoidCallback onDeleted;

  Future<UnfinishedLinkWork> unfinishedLinkWork(String videoKey) async {
    final session = await (await stores.topics()).session(videoKey);
    return UnfinishedLinkWork(
      videoKey: videoKey,
      session: session,
      joinedClipIds: await _unfinishedJoinedClips(videoKey),
    );
  }

  /// Deletes the session, and each joined clip's fine-tune and kept file.
  /// Reels already made from them stay.
  Future<void> delete(UnfinishedLinkWork work) async {
    await (await stores.topics()).deleteSession(work.videoKey);
    final drafts = await stores.drafts();
    final sources = await stores.sources();
    for (final videoId in work.joinedClipIds) {
      await drafts.delete(videoId);
      await sources.deleteVideo(videoId);
    }
    onDeleted();
  }

  Future<List<String>> _unfinishedJoinedClips(String videoKey) async {
    final drafts = await (await stores.drafts()).list();
    return [
      for (final draft in drafts)
        if ((await stores.links.read(draft.videoId))?.videoKey == videoKey)
          draft.videoId,
    ];
  }
}

final unfinishedLinkWorksProvider = Provider<UnfinishedLinkWorks>((ref) {
  return UnfinishedLinkWorks(
    UnfinishedLinkWorkStores(
      topics: () => ref.read(topicStoreProvider.future),
      drafts: () => ref.read(fineTuneDraftStoreProvider.future),
      links: ref.read(linkedClipStoreProvider),
      sources: () => ref.read(sourceCacheProvider.future),
    ),
    onDeleted: () {
      if (!ref.mounted) {
        return;
      }
      ref
        ..invalidate(linkSessionsProvider)
        ..invalidate(fineTuneDraftsProvider)
        ..invalidate(isVideoKeptProvider)
        ..invalidate(linkedClipProvider);
    },
  );
});
