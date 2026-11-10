import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/appearance/domain/theme_choice.dart';

const _themeKey = 'appearance.theme';

/// The saved theme choice (spec FR-32), kept by its name.
class ThemeChoiceStore {
  const ThemeChoiceStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  /// Nothing saved, or a name this version doesn't know, means System.
  Future<ThemeChoice> read() async {
    final savedName = await _preferences.getString(_themeKey);
    return ThemeChoice.values.asNameMap()[savedName] ?? ThemeChoice.system;
  }

  Future<void> save(ThemeChoice choice) =>
      _preferences.setString(_themeKey, choice.name);
}

final themeChoiceStoreProvider = Provider<ThemeChoiceStore>(
  (ref) => ThemeChoiceStore(ref.watch(preferencesProvider)),
);
