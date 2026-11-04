import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
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

/// Reels, scripts and kept fine-tunes in one list, newest first. A kept
/// fine-tune replaces the script row of its video and language, so the
/// video shows once.
List<RecentEntry> recentEntries({
  required List<RecentReel> reels,
  required List<SavedScript> scripts,
  required List<SavedFineTune> fineTunes,
}) {
  final continued = {for (final fineTune in fineTunes) fineTune.key};
  return [
    for (final reel in reels) ReelEntry(reel),
    for (final script in scripts)
      if (!continued.contains(script.key)) ScriptEntry(script),
    for (final fineTune in fineTunes) FineTuneEntry(fineTune),
  ]..sort((a, b) => b.sortedAt.compareTo(a.sortedAt));
}
