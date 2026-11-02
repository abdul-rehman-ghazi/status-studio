import 'dart:io';

import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// Deletes the per-video folders under [root] whose newest file is older
/// than [maxAge] (spec §4 Storage). Returns how many were deleted.
Future<int> deleteStaleSources(
  Directory root, {
  required DateTime now,
  Duration maxAge = const Duration(days: 7),
}) async {
  if (!await root.exists()) {
    return 0;
  }
  var deleted = 0;
  await for (final entry in root.list()) {
    if (entry is Directory && now.difference(_lastChange(entry)) > maxAge) {
      await entry.delete(recursive: true);
      deleted++;
    }
  }
  return deleted;
}

/// When a file in [folder] last changed, so a clip fetched today keeps the
/// video's older audio too. Reading a cached file doesn't count: the spec
/// deletes caches by age, not by use. The folder's own time is used only
/// when it's empty, since adding files moves it.
DateTime _lastChange(Directory folder) {
  final files = folder.listSync(recursive: true).whereType<File>();
  if (files.isEmpty) {
    return folder.statSync().modified;
  }
  return files
      .map((file) => file.lastModifiedSync())
      .reduce((newest, time) => time.isAfter(newest) ? time : newest);
}

/// Startup housekeeping: stale media caches and old saved scripts
/// (FR-14: 90 days, at most 200 videos). Each runs even if the other
/// fails; the first failure is then rethrown to be reported.
Future<void> cleanUpOnStart({
  required Future<Directory> sources,
  required Future<TranscriptStore> scripts,
  required DateTime now,
}) async {
  await Future.wait([
    sources.then((root) => deleteStaleSources(root, now: now)),
    scripts.then((store) => store.prune()),
  ]);
}
