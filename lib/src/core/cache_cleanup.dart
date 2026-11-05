import 'dart:io';

import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// Deletes the `sources/<id>` folders in [sources] that were imported but
/// never scripted: no `transcripts/<id>` folder in [transcripts] at all, and
/// nothing in them changed for [maxAge] (spec §4 Storage). A video whose
/// script or fine-tune draft is kept is never deleted here; the 90-day
/// transcript prune removes it, folder and all. Returns how many were
/// deleted.
Future<int> deleteOrphanedSources(
  Directory sources, {
  required Directory transcripts,
  required DateTime now,
  Duration maxAge = const Duration(days: 7),
}) async {
  if (!await sources.exists()) {
    return 0;
  }
  var deleted = 0;
  await for (final entry in sources.list()) {
    if (entry is Directory &&
        !_hasTranscripts(entry, transcripts) &&
        now.difference(_lastChange(entry)) > maxAge) {
      await _deleteIfPresent(entry);
      deleted++;
    }
  }
  return deleted;
}

bool _hasTranscripts(Directory source, Directory transcripts) {
  final videoId = source.uri.pathSegments.lastWhere((name) => name.isNotEmpty);
  return Directory('${transcripts.path}/$videoId').existsSync();
}

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

/// Startup housekeeping: old saved scripts with their videos (FR-14: 90
/// days, at most 200 videos) and videos imported but never scripted. Each
/// runs even if the other fails; the first failure is then rethrown to be
/// reported.
Future<void> cleanUpOnStart({
  required Future<Directory> sources,
  required Future<TranscriptStore> scripts,
  required DateTime now,
}) async {
  await Future.wait([
    scripts.then((store) => store.prune()),
    Future.wait([sources, scripts]).then(
      (both) => deleteOrphanedSources(
        both[0] as Directory,
        transcripts: (both[1] as TranscriptStore).root,
        now: now,
      ),
    ),
  ]);
}
