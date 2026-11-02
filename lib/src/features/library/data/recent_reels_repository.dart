import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';

const _key = 'recentReels';

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
    } on FormatException {
      unreadable.add(entry);
    } on TypeError {
      unreadable.add(entry);
    }
  }
  return (reels: reels, unreadable: unreadable);
}

/// Unlinking is quick even for a large MP4, so this needn't be async.
void _deleteFiles(RecentReel reel) {
  for (final path in [reel.videoPath, reel.thumbnailPath]) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

final recentReelsRepositoryProvider = Provider<RecentReelsRepository>(
  (ref) => RecentReelsRepository(SharedPreferencesAsync()),
);
