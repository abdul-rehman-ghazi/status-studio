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

  /// Reels whose MP4 still exists. A corrupt list reads as empty rather
  /// than stopping the app from opening.
  Future<List<RecentReel>> load() async {
    final reels = await _stored();
    return reels.where((reel) => File(reel.videoPath).existsSync()).toList();
  }

  /// Adds [reel] as the newest; the oldest beyond [maximum] go, files too.
  Future<void> add(RecentReel reel) async {
    final reels = [reel, ...await _stored()];
    final kept = reels.take(maximum).toList();
    for (final dropped in reels.skip(maximum)) {
      _deleteFiles(dropped);
    }
    await _save(kept);
  }

  Future<void> delete(String id) async {
    final reels = await _stored();
    for (final doomed in reels.where((reel) => reel.id == id)) {
      _deleteFiles(doomed);
    }
    await _save(reels.where((reel) => reel.id != id).toList());
  }

  Future<List<RecentReel>> _stored() async {
    final json = await preferences.getString(_key);
    if (json == null) {
      return [];
    }
    try {
      final entries = jsonDecode(json) as List<Object?>;
      return [
        for (final entry in entries)
          RecentReel.fromJson(entry! as Map<String, Object?>),
      ];
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> _save(List<RecentReel> reels) => preferences.setString(
    _key,
    jsonEncode([for (final reel in reels) reel.toJson()]),
  );
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
