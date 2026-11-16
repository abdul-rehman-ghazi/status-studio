import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/join/domain/linked_clip.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/library/domain/video_history.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/topic/application/link_sessions_controller.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// History's groups (spec FR-44), newest activity first. Read again each
/// time History opens, since `topics/` changes without telling anyone.
final historyProvider = FutureProvider.autoDispose<List<VideoHistory>>((
  ref,
) async {
  final reels = await ref.watch(recentReelsProvider.future);
  final scripts = await ref.watch(savedScriptsProvider.future);
  final fineTunes = await ref.watch(fineTuneDraftsProvider.future);
  final sessions = await ref.watch(linkSessionsProvider.future);
  final videoIds = {
    for (final reel in reels) reel.sourceVideoId,
    for (final script in scripts) script.video.videoId,
    for (final fineTune in fineTunes) fineTune.draft.videoId,
  };
  final joinedClips = <String, LinkedClip>{
    for (final videoId in videoIds)
      videoId: ?await ref.watch(linkedClipProvider(videoId).future),
  };
  final topics = await ref.watch(topicStoreProvider.future);
  final videoKeys = await topics.videoIds();
  return historyOf(
    HistorySources(
      reels: reels,
      scripts: scripts,
      fineTunes: fineTunes,
      linkSessions: sessions,
      links: LinkFacts(
        joinedClips: joinedClips,
        videos: await _savedLinkedVideos(topics, videoKeys),
        transcripts: {
          for (final videoKey in videoKeys)
            videoKey: await topics.savedScripts(videoKey),
        },
        localVideos: await _localVideosOfReels(
          await ref.watch(transcriptStoreProvider.future),
          reels,
        ),
      ),
    ),
  );
});

Future<Map<String, LinkedVideo>> _savedLinkedVideos(
  TopicStore topics,
  List<String> videoKeys,
) async => {
  for (final videoKey in videoKeys)
    videoKey: ?await topics.savedVideo(videoKey),
};

/// A local video whose scripts were deleted is still known by the title
/// and length kept beside them, while that lasts.
Future<Map<String, SourceVideo>> _localVideosOfReels(
  TranscriptStore scripts,
  List<RecentReel> reels,
) async {
  final videos = <String, SourceVideo>{};
  for (final reel in reels) {
    if (reel.videoKey != null || videos.containsKey(reel.sourceVideoId)) {
      continue;
    }
    try {
      videos[reel.sourceVideoId] = await scripts.loadVideo(reel.sourceVideoId);
    } on NoSavedVideoException {
      continue;
    }
  }
  return videos;
}
