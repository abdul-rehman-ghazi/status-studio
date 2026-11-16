import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';

const _key = 'recentReels';
const _strayFileAge = Duration(hours: 1);

/// Finished reels, newest first, at most [maximum] (spec FR-11). Entries
/// live in preferences; their MP4s and thumbnails in `documents/reels/`.
class RecentReelsRepository {
  RecentReelsRepository(this.preferences);

  static const maximum = 50;

  final SharedPreferencesAsync preferences;

  /// Reels whose MP4 still exists. Entries this version can't read are
  /// left out but kept in storage, so a corrupt or newer entry never
  /// stops the app from opening and is never written over.
  Future<List<RecentReel>> load() async {
    final stored = await _stored();
    return stored.reels
        .where((reel) => File(reel.videoPath).existsSync())
        .toList();
  }

  /// Adds [reel] as the newest; the oldest beyond [maximum] go, files too.
  Future<void> add(RecentReel reel) async {
    final stored = await _stored();
    final reels = [reel, ...stored.reels];
    for (final dropped in reels.skip(maximum)) {
      _deleteFiles(dropped);
    }
    await _save((
      reels: reels.take(maximum).toList(),
      unreadable: stored.unreadable,
    ));
  }

  Future<void> delete(String id) async {
    final stored = await _stored();
    for (final doomed in stored.reels.where((reel) => reel.id == id)) {
      _deleteFiles(doomed);
    }
    await _save((
      reels: stored.reels.where((reel) => reel.id != id).toList(),
      unreadable: stored.unreadable,
    ));
  }

  /// Deletes the stored reels that recorded no source (made before M54,
  /// spec FR-44), with their MP4s and thumbnails. Other unreadable entries
  /// stay untouched.
  Future<void> deleteWithoutSource() async {
    final stored = await _stored();
    final withoutSource = stored.unreadable.where(_hasNoSource).toList();
    if (withoutSource.isEmpty) {
      return;
    }
    withoutSource.forEach(_deleteEntryFiles);
    await _save((
      reels: stored.reels,
      unreadable: [
        for (final entry in stored.unreadable)
          if (!_hasNoSource(entry)) entry,
      ],
    ));
  }

  /// Deletes the files in [folder] that no stored entry names as its MP4
  /// or thumbnail and that haven't changed for an hour before [now] (spec
  /// FR-49): what a render killed halfway leaves. The hour spares a render
  /// still running when the app's screen starts again.
  Future<void> deleteStrayFiles(
    Directory folder, {
    required DateTime now,
  }) async {
    final stored = await _stored();
    // A list that can't be read at all names nothing, so nothing is known
    // to be stray.
    if (stored.unreadable.any((entry) => entry is! Map<String, Object?>) ||
        !await folder.exists()) {
      return;
    }
    final named = _namedFiles(stored);
    await for (final entry in folder.list()) {
      if (entry is File &&
          !named.contains(_fileName(entry.path)) &&
          now.difference(entry.lastModifiedSync()) > _strayFileAge) {
        await entry.delete();
      }
    }
  }

  Future<_StoredReels> _stored() async {
    final json = await preferences.getString(_key);
    if (json == null) {
      return (reels: <RecentReel>[], unreadable: <Object?>[]);
    }
    try {
      return _parseEntries(jsonDecode(json) as List<Object?>);
    } on FormatException {
      return (reels: <RecentReel>[], unreadable: <Object?>[json]);
    } on TypeError {
      return (reels: <RecentReel>[], unreadable: <Object?>[json]);
    }
  }

  Future<void> _save(_StoredReels stored) => preferences.setString(
    _key,
    jsonEncode([
      for (final reel in stored.reels) reel.toJson(),
      ...stored.unreadable,
    ]),
  );
}

/// Readable reels, and the raw entries that weren't, kept to write back.
typedef _StoredReels = ({List<RecentReel> reels, List<Object?> unreadable});

_StoredReels _parseEntries(List<Object?> entries) {
  final reels = <RecentReel>[];
  final unreadable = <Object?>[];
  for (final entry in entries) {
    try {
      reels.add(RecentReel.fromJson(entry! as Map<String, Object?>));
    } on Exception {
      unreadable.add(entry);
    } on TypeError {
      unreadable.add(entry);
    }
  }
  return (reels: reels, unreadable: unreadable);
}

bool _hasNoSource(Object? entry) =>
    entry is Map<String, Object?> && entry['sourceVideoId'] == null;

/// An unreadable entry's files, as far as its paths can be read.
void _deleteEntryFiles(Object? entry) {
  if (entry is! Map<String, Object?>) {
    return;
  }
  _entryPaths(entry).forEach(_deleteFile);
}

List<String> _entryPaths(Map<String, Object?> entry) => [
  for (final path in [entry['videoPath'], entry['thumbnailPath']])
    if (path is String) path,
];

/// The names of every file a stored entry points at, readable or not.
Set<String> _namedFiles(_StoredReels stored) => {
  for (final reel in stored.reels) ...[
    _fileName(reel.videoPath),
    _fileName(reel.thumbnailPath),
  ],
  for (final entry in stored.unreadable.whereType<Map<String, Object?>>())
    ..._entryPaths(entry).map(_fileName),
};

/// Compared by name, since every reel's files sit in the one folder and a
/// stored path may spell the app's folder differently (`/data/user/0`).
String _fileName(String path) => path.substring(path.lastIndexOf('/') + 1);

void _deleteFile(String path) {
  final file = File(path);
  if (file.existsSync()) {
    file.deleteSync();
  }
}

/// Unlinking is quick even for a large MP4, so this needn't be async.
void _deleteFiles(RecentReel reel) {
  for (final path in [reel.videoPath, reel.thumbnailPath]) {
    _deleteFile(path);
  }
}

final recentReelsRepositoryProvider = Provider<RecentReelsRepository>(
  (ref) => RecentReelsRepository(ref.watch(preferencesProvider)),
);
