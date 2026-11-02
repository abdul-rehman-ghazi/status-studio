import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';

const _lastUpdateKey = 'ytdlp.lastUpdate';

/// YouTube changes often and yt-dlp follows within days, so it's updated
/// weekly (about 3 MB), and from Settings on demand.
const _updateEvery = Duration(days: 7);

class YtDlpUpdater {
  YtDlpUpdater(this.ytDlp, this.preferences);

  final YtDlp ytDlp;
  final SharedPreferencesAsync preferences;

  /// Updates when the last update is a week old, or there never was one.
  Future<void> updateIfDue(DateTime now) async {
    final stored = await preferences.getString(_lastUpdateKey);
    final last = stored == null ? null : DateTime.tryParse(stored);
    if (last != null && now.difference(last) < _updateEvery) {
      return;
    }
    await updateNow(now);
  }

  Future<YtDlpUpdate> updateNow(DateTime now) async {
    final result = await ytDlp.update();
    await preferences.setString(_lastUpdateKey, now.toIso8601String());
    return result;
  }
}

final ytDlpUpdaterProvider = Provider<YtDlpUpdater>(
  (ref) =>
      YtDlpUpdater(ref.watch(ytDlpProvider), ref.watch(preferencesProvider)),
);
