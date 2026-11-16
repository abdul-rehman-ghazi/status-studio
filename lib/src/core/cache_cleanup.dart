import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/data/video_fingerprint.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

const _unusedSourceAge = Duration(days: 7);

/// What a `transcripts/<videoId>/` folder holds once a video is imported:
/// its title and last-used time. Anything else is work worth keeping.
const _titleOnlyNames = {'video.json', 'last_used'};

/// What keeps a kept video from being deleted as unused (spec FR-47): a
/// script, Groq progress or a fine-tune draft beside its title, or a reel
/// made from it, whose New reopens Fine-tune on it.
@immutable
class KeptWork {
  const KeptWork({required this.transcripts, required this.reelSourceIds});

  final Directory transcripts;
  final Set<String> reelSourceIds;

  bool keeps(String videoId) =>
      reelSourceIds.contains(videoId) || _hasSavedWork(videoId);

  bool _hasSavedWork(String videoId) {
    final folder = Directory('${transcripts.path}/$videoId');
    if (!folder.existsSync()) {
      return false;
    }
    return folder.listSync().any(
      (entry) => !_titleOnlyNames.contains(_nameOf(entry)),
    );
  }
}

/// Deletes the `sources/<id>` folders in [sources] that [kept] doesn't keep
/// and in which nothing changed for 7 days (spec §4 Storage, FR-47): a
/// video imported and left without a script, a fine-tune or a reel has no
/// History group, so nothing could reach it. After 90 days unused a kept
/// video's files go even with a script, which stays (FR-44). Returns how
/// many were deleted.
Future<int> deleteOrphanedSources(
  Directory sources, {
  required KeptWork kept,
  required DateTime now,
}) async {
  if (!await sources.exists()) {
    return 0;
  }
  var deleted = 0;
  await for (final entry in sources.list()) {
    if (entry is Directory &&
        !kept.keeps(_nameOf(entry)) &&
        now.difference(_lastChange(entry)) > _unusedSourceAge) {
      await _deleteIfPresent(entry);
      deleted++;
    }
  }
  return deleted;
}

String _nameOf(FileSystemEntity entry) =>
    entry.uri.pathSegments.lastWhere((name) => name.isNotEmpty);

/// A prune running at the same time may have deleted it first.
Future<void> _deleteIfPresent(Directory folder) async {
  if (await folder.exists()) {
    await folder.delete(recursive: true);
  }
}

/// When [folder] or a file in it last changed. The folder's own time counts
/// because moving a file in keeps the file's old time. Reading a file
/// doesn't change either: the spec deletes by age, not by use.
DateTime _lastChange(Directory folder) {
  final times = [
    folder.statSync().modified,
    for (final file in folder.listSync(recursive: true).whereType<File>())
      file.lastModifiedSync(),
  ];
  return times.reduce((newest, time) => time.isAfter(newest) ? time : newest);
}

/// Deletes the folders in [root] whose name isn't a video fingerprint
/// (`v_…`): they belong to videos from before M23 that can no longer be
/// reached (spec FR-1). Files are left alone. Returns how many were deleted.
Future<int> deleteFoldersWithoutFingerprint(Directory root) async {
  if (!await root.exists()) {
    return 0;
  }
  var deleted = 0;
  await for (final entry in root.list()) {
    if (entry is Directory && !isVideoId(_nameOf(entry))) {
      await _deleteIfPresent(entry);
      deleted++;
    }
  }
  return deleted;
}

/// Where the start-up cleanup looks.
@immutable
class CleanupPlaces {
  const CleanupPlaces({
    required this.sources,
    required this.scripts,
    required this.reelSourceIds,
  });

  final Future<Directory> sources;
  final Future<TranscriptStore> scripts;

  /// Read only when the unused-video pass starts, so a failure to read the
  /// reels can't surface before anything listens for it.
  final Future<Set<String>> Function() reelSourceIds;
}

/// Startup housekeeping: kept videos unused for 90 days, their scripts
/// staying (FR-44; until M54 the scripts went too, and beyond 200 videos),
/// kept videos nothing can reach (FR-47), and the folders of videos from
/// before M23. Each runs even if another fails; the first failure is then
/// rethrown to be reported.
Future<void> cleanUpOnStart(
  CleanupPlaces places, {
  required DateTime now,
}) async {
  // First and alone: the other passes list and delete inside these folders.
  Object? firstFailure;
  try {
    await Future.wait([
      places.sources.then(deleteFoldersWithoutFingerprint),
      places.scripts.then(
        (store) => deleteFoldersWithoutFingerprint(store.root),
      ),
    ]);
  } on Object catch (failure) {
    firstFailure = failure;
  }
  await Future.wait([
    places.scripts.then((store) => store.deleteUnusedKeptVideos()),
    _deleteUnreachableSources(places, now),
  ]);
  if (firstFailure != null) {
    throw firstFailure;
  }
}

Future<int> _deleteUnreachableSources(
  CleanupPlaces places,
  DateTime now,
) async {
  final kept = KeptWork(
    transcripts: (await places.scripts).root,
    reelSourceIds: await places.reelSourceIds(),
  );
  return deleteOrphanedSources(await places.sources, kept: kept, now: now);
}
