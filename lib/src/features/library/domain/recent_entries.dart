import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

/// A row of Home's Recent list (spec FR-11).
@immutable
sealed class RecentEntry {
  const RecentEntry();

  DateTime get sortedAt;
}

class ReelEntry extends RecentEntry {
  const ReelEntry(this.reel);

  final RecentReel reel;

  @override
  DateTime get sortedAt => reel.createdAt;
}

class ScriptEntry extends RecentEntry {
  const ScriptEntry(this.script);

  final SavedScript script;

  @override
  DateTime get sortedAt => script.saved.savedAt;
}

/// A kept fine-tune to continue (spec FR-24).
class FineTuneEntry extends RecentEntry {
  const FineTuneEntry(this.fineTune);

  final SavedFineTune fineTune;

  @override
  DateTime get sortedAt => fineTune.draft.savedAt;
}

/// A link left on Review cuts to continue (spec FR-38).
class LinkSessionEntry extends RecentEntry {
  const LinkSessionEntry(this.session);

  final LinkSession session;

  @override
  DateTime get sortedAt => session.savedAt;
}

/// What Recent lists, before it is merged.
class RecentLists {
  const RecentLists({
    required this.reels,
    required this.scripts,
    required this.fineTunes,
    required this.linkSessions,
  });

  final List<RecentReel> reels;
  final List<SavedScript> scripts;
  final List<SavedFineTune> fineTunes;
  final List<LinkSession> linkSessions;
}

/// Reels, scripts, kept fine-tunes and links in one list, newest first. A
/// kept fine-tune replaces every script row of its video, so the video
/// shows once (M30: one fine-tune per video).
List<RecentEntry> recentEntries(RecentLists lists) {
  final continued = {
    for (final fineTune in lists.fineTunes) fineTune.draft.videoId,
  };
  return [
    for (final reel in lists.reels) ReelEntry(reel),
    for (final script in lists.scripts)
      if (!continued.contains(script.video.videoId)) ScriptEntry(script),
    for (final fineTune in lists.fineTunes) FineTuneEntry(fineTune),
    for (final session in lists.linkSessions) LinkSessionEntry(session),
  ]..sort((a, b) => b.sortedAt.compareTo(a.sortedAt));
}
