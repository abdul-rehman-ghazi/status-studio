import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

const _outputLanguageKey = 'topic.outputLanguage';

/// The output language last used for Get the script, preselected next time
/// on Source and From a link (spec FR-51).
class OutputLanguageStore {
  const OutputLanguageStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  /// Nothing saved, or a code not in [outputLanguages], means Urdu.
  Future<ScriptLanguage> read() async {
    final savedCode = await _preferences.getString(_outputLanguageKey);
    for (final language in outputLanguages) {
      if (language.whisperCode == savedCode) {
        return language;
      }
    }
    return ScriptLanguage.urdu;
  }

  Future<void> save(ScriptLanguage language) =>
      _preferences.setString(_outputLanguageKey, language.whisperCode);
}

final outputLanguageStoreProvider = Provider<OutputLanguageStore>(
  (ref) => OutputLanguageStore(ref.watch(preferencesProvider)),
);
