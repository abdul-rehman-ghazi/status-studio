import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/transcript/domain/groq_usage.dart';

const _usageKey = 'groq.audioUsage';

/// The audio counted against Groq's allowance (spec FR-45), kept apart
/// from the key, which lives in secure storage.
class GroqUsageStore {
  const GroqUsageStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  /// An unreadable entry counts as nothing sent: the figure can only be
  /// too high, never stop a script.
  Future<GroqUsage> saved() async {
    final stored = await _preferences.getString(_usageKey);
    if (stored == null) {
      return GroqUsage.none;
    }
    try {
      return GroqUsage.fromJson(jsonDecode(stored) as Map<String, Object?>);
    } on Object {
      return GroqUsage.none;
    }
  }

  Future<void> save(GroqUsage usage) =>
      _preferences.setString(_usageKey, jsonEncode(usage.toJson()));

  Future<void> forget() => _preferences.remove(_usageKey);
}

final groqUsageStoreProvider = Provider<GroqUsageStore>(
  (ref) => GroqUsageStore(ref.watch(preferencesProvider)),
);
