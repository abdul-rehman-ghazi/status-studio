import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/transcript/domain/groq_allowance.dart';

const _allowanceKey = 'groq.audioAllowance';

/// The last audio allowance Groq reported (spec FR-45), kept apart from the
/// key, which lives in secure storage.
class GroqAllowanceStore {
  const GroqAllowanceStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  /// `null` when Groq hasn't reported one yet. An unreadable entry counts
  /// as none: the next script piece writes a fresh one.
  Future<GroqAllowance?> saved() async {
    final stored = await _preferences.getString(_allowanceKey);
    if (stored == null) {
      return null;
    }
    try {
      return GroqAllowance.fromJson(jsonDecode(stored) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  Future<void> save(GroqAllowance allowance) =>
      _preferences.setString(_allowanceKey, jsonEncode(allowance.toJson()));

  Future<void> forget() => _preferences.remove(_allowanceKey);
}

final groqAllowanceStoreProvider = Provider<GroqAllowanceStore>(
  (ref) => GroqAllowanceStore(ref.watch(preferencesProvider)),
);
