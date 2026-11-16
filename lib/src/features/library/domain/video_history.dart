import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/join/domain/linked_clip.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

/// Which video a History group is (spec FR-44).
@immutable
sealed class HistoryVideo {
  const HistoryVideo();
}

/// A linked video, by its key (spec FR-50).
final class LinkedVideoKey extends HistoryVideo {
  const LinkedVideoKey(this.videoKey);

  final String videoKey;

  @override
  bool operator ==(Object other) =>
      other is LinkedVideoKey && other.videoKey == videoKey;

  @override
  int get hashCode => videoKey.hashCode;
}

/// A video shared or chosen on the phone, by its fingerprint (FR-1).
final class LocalVideoKey extends HistoryVideo {
  const LocalVideoKey(this.videoId);

  final String videoId;

  @override
  bool operator ==(Object other) =>
      other is LocalVideoKey && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

/// A video's one piece of unfinished work (spec FR-43, FR-44).
@immutable
sealed class UnfinishedWork {
  const UnfinishedWork();

  DateTime get savedAt;
}

/// A link left on Review cuts (FR-38).
final class UnfinishedLink extends UnfinishedWork {
  const UnfinishedLink(this.session);

  final LinkSession session;

  @override
  DateTime get savedAt => session.savedAt;
}

/// A kept fine-tune (FR-24), of a local video or a joined link clip.
final class UnfinishedFineTune extends UnfinishedWork {
  const UnfinishedFineTune(this.fineTune);

  final SavedFineTune fineTune;

  @override
  DateTime get savedAt => fineTune.draft.savedAt;
}

/// One video on History (spec FR-44): its row, its unfinished work and
/// its reels, newest first.
@immutable
class VideoHistory {
  const VideoHistory({
    required this.key,
    required this.title,
    required this.facts,
    required this.unfinished,
    required this.reels,
    required this.lastActivity,
  });

  final HistoryVideo key;
  final String title;
  final VideoFacts facts;
  final UnfinishedWork? unfinished;
  final List<RecentReel> reels;

  /// A reel made, a script saved or unfinished work saved, the newest.
  final DateTime lastActivity;

  bool get scriptSaved => facts.scriptLanguage != null;
}

/// What a group knows about its video, for its row and for New.
@immutable
class VideoFacts {
  const VideoFacts({
    this.length,
    this.thumbnailUrl,
    this.scriptLanguage,
    this.linkedVideo,
    this.localVideo,
  });

  final Duration? length;

  /// YouTube's picture for a link; a local video's frame is cut from its
  /// kept file instead.
  final String? thumbnailUrl;

  /// The newest saved script's language; null when none is saved.
  final ScriptLanguage? scriptLanguage;

  /// What New opens Review cuts with; null for a local video, or a link
  /// whose facts were never kept.
  final LinkedVideo? linkedVideo;

  /// What New opens Fine-tune on; null for a link.
  final SourceVideo? localVideo;
}

/// Everything History groups (spec FR-44).
@immutable
class HistorySources {
  const HistorySources({
    required this.reels,
    required this.scripts,
    required this.fineTunes,
    required this.linkSessions,
    required this.links,
  });

  final List<RecentReel> reels;
  final List<SavedScript> scripts;
  final List<SavedFineTune> fineTunes;
  final List<LinkSession> linkSessions;
  final LinkFacts links;
}

/// What is kept about linked videos and the clips joined from them.
@immutable
class LinkFacts {
  const LinkFacts({
    required this.joinedClips,
    required this.videos,
    required this.transcripts,
    required this.localVideos,
  });

  /// `link.json` of each joined clip, by the clip's fingerprint.
  final Map<String, LinkedClip> joinedClips;

  /// `video.json` of each linked video, by video key.
  final Map<String, LinkedVideo> videos;

  /// The transcripts saved under `topics/`, by video key.
  final Map<String, List<SavedLinkScript>> transcripts;

  /// Title and length of local videos known only from their reels.
  final Map<String, SourceVideo> localVideos;
}

const _youTubeScriptPrefix = 'v_yt_';

/// One group per video, newest activity first (spec FR-44). A `v_yt_<ID>`
/// script and every joined clip fold into their YouTube video; a joined
/// clip is never a group of its own. A video with nothing to show (no
/// reel, script or unfinished work) has no group.
List<VideoHistory> historyOf(HistorySources sources) {
  final groups = <HistoryVideo, _Group>{};
  _Group groupOf(HistoryVideo key) => groups.putIfAbsent(key, _Group.new);
  HistoryVideo keyOf(String videoId) => _keyOf(videoId, sources.links);

  for (final reel in sources.reels) {
    final videoKey = reel.videoKey;
    groupOf(
      videoKey == null ? keyOf(reel.sourceVideoId) : LinkedVideoKey(videoKey),
    ).addReel(reel);
  }
  for (final script in sources.scripts) {
    groupOf(keyOf(script.video.videoId)).addScript(script);
  }
  for (final fineTune in sources.fineTunes) {
    groupOf(keyOf(fineTune.draft.videoId))
        .addUnfinished(UnfinishedFineTune(fineTune));
  }
  for (final session in sources.linkSessions) {
    groupOf(LinkedVideoKey(session.request.source.key))
        .addUnfinished(UnfinishedLink(session));
  }
  for (final MapEntry(key: videoKey, value: saved)
      in sources.links.transcripts.entries) {
    saved.forEach(groupOf(LinkedVideoKey(videoKey)).addLinkScript);
  }
  return [
    for (final MapEntry(:key, :value) in groups.entries)
      if (value.hasContent) value.build(key, sources.links),
  ]..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
}

HistoryVideo _keyOf(String videoId, LinkFacts links) {
  if (videoId.startsWith(_youTubeScriptPrefix)) {
    return LinkedVideoKey(videoId.substring(_youTubeScriptPrefix.length));
  }
  if (links.joinedClips[videoId] case final joined?) {
    return LinkedVideoKey(joined.videoKey);
  }
  return LocalVideoKey(videoId);
}

/// A group as it is gathered.
class _Group {
  final reels = <RecentReel>[];
  final videoScripts = <SavedScript>[];
  final linkScripts = <SavedLinkScript>[];
  UnfinishedWork? unfinished;

  bool get hasContent =>
      reels.isNotEmpty ||
      videoScripts.isNotEmpty ||
      linkScripts.isNotEmpty ||
      unfinished != null;

  void addReel(RecentReel reel) => reels.add(reel);

  void addScript(SavedScript script) => videoScripts.add(script);

  void addLinkScript(SavedLinkScript script) => linkScripts.add(script);

  /// Only one should exist (FR-43); work kept before M53 may leave two,
  /// and the newest is shown.
  void addUnfinished(UnfinishedWork work) {
    final kept = unfinished;
    if (kept == null || work.savedAt.isAfter(kept.savedAt)) {
      unfinished = work;
    }
  }

  VideoHistory build(HistoryVideo key, LinkFacts links) {
    reels.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final facts = switch (key) {
      LinkedVideoKey(:final videoKey) => _linkFacts(videoKey, links),
      LocalVideoKey(:final videoId) => _localFacts(videoId, links),
    };
    return VideoHistory(
      key: key,
      title: _titleOf(facts, key),
      facts: facts,
      unfinished: unfinished,
      reels: List.unmodifiable(reels),
      lastActivity: _lastActivity(),
    );
  }

  /// A joined clip's own lyrics scripts fold in, but only the YouTube
  /// video's script counts as its script.
  VideoFacts _linkFacts(String videoKey, LinkFacts links) {
    final session = switch (unfinished) {
      UnfinishedLink(:final session) => session,
      _ => null,
    };
    final video =
        links.videos[videoKey] ??
        switch (session?.request.source) {
          LinkedMoments(:final video) => video,
          _ => null,
        };
    final youTubeScripts = [
      for (final script in videoScripts)
        if (script.video.videoId.startsWith(_youTubeScriptPrefix)) script,
    ];
    return VideoFacts(
      length: video?.duration ?? youTubeScripts.firstOrNull?.video.duration,
      thumbnailUrl: video?.thumbnailUrl,
      scriptLanguage: _newestLinkLanguage(youTubeScripts),
      linkedVideo: video,
    );
  }

  VideoFacts _localFacts(String videoId, LinkFacts links) {
    final newest = _newestScript(videoScripts);
    final video =
        newest?.video ??
        switch (unfinished) {
          UnfinishedFineTune(:final fineTune) => fineTune.video,
          _ => null,
        } ??
        links.localVideos[videoId];
    return VideoFacts(
      length: video?.duration,
      scriptLanguage: newest?.language,
      localVideo: video,
    );
  }

  ScriptLanguage? _newestLinkLanguage(List<SavedScript> youTubeScripts) {
    final dated = [
      ...linkScripts,
      for (final script in youTubeScripts)
        (language: script.language, savedAt: script.saved.savedAt),
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return dated.firstOrNull?.language;
  }

  String _titleOf(VideoFacts facts, HistoryVideo key) =>
      facts.linkedVideo?.title ??
      facts.localVideo?.title ??
      _newestScript(videoScripts)?.video.title ??
      reels.firstOrNull?.title ??
      switch (key) {
        LinkedVideoKey(:final videoKey) => videoKey,
        LocalVideoKey(:final videoId) => videoId,
      };

  DateTime _lastActivity() => [
    for (final reel in reels) reel.createdAt,
    for (final script in videoScripts) script.saved.savedAt,
    for (final script in linkScripts) script.savedAt,
    ?unfinished?.savedAt,
  ].reduce((a, b) => a.isAfter(b) ? a : b);
}

SavedScript? _newestScript(List<SavedScript> scripts) => scripts.isEmpty
    ? null
    : scripts.reduce(
        (a, b) => b.saved.savedAt.isAfter(a.saved.savedAt) ? b : a,
      );
