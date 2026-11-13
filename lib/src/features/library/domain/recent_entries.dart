import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';

/// Home's Carry on shows at most this many (spec FR-44).
const carryOnLimit = 3;

/// A row of Home's Carry on (spec FR-44; Recent's, FR-11, until M54).
@immutable
sealed class RecentEntry {
  const RecentEntry();

  DateTime get sortedAt;
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

/// The unfinished work Carry on lists, before it is merged.
class RecentLists {
  const RecentLists({required this.fineTunes, required this.linkSessions});

  final List<SavedFineTune> fineTunes;
  final List<LinkSession> linkSessions;
}

/// Kept fine-tunes and links in one list, newest first, at most
/// [carryOnLimit]. Reels and scripts are on History since M54 (FR-44).
List<RecentEntry> recentEntries(RecentLists lists) {
  final entries = <RecentEntry>[
    for (final fineTune in lists.fineTunes) FineTuneEntry(fineTune),
    for (final session in lists.linkSessions) LinkSessionEntry(session),
  ]..sort((a, b) => b.sortedAt.compareTo(a.sortedAt));
  return entries.take(carryOnLimit).toList();
}
