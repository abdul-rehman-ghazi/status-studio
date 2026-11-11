import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';

const _lookKey = 'caption.look';
const _boxColoursKey = 'caption.boxColours';
const _shadowColoursKey = 'caption.shadowColours';

/// The caption appearance used last, so a new reel starts from it
/// (spec FR-7). Kept by name.
class CaptionAppearanceStore {
  const CaptionAppearanceStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  /// A name missing, or one this version doesn't know, reads as the default.
  Future<CaptionAppearance> read() async {
    const fallback = CaptionAppearance();
    final names = await _preferences.getAll(
      allowList: {_lookKey, _boxColoursKey, _shadowColoursKey},
    );
    return CaptionAppearance(
      look: CaptionLook.values.asNameMap()[names[_lookKey]] ?? fallback.look,
      boxColours:
          BoxColours.values.asNameMap()[names[_boxColoursKey]] ??
          fallback.boxColours,
      shadowColours:
          ShadowColours.values.asNameMap()[names[_shadowColoursKey]] ??
          fallback.shadowColours,
    );
  }

  Future<void> save(CaptionAppearance appearance) async {
    await _preferences.setString(_lookKey, appearance.look.name);
    await _preferences.setString(_boxColoursKey, appearance.boxColours.name);
    await _preferences.setString(
      _shadowColoursKey,
      appearance.shadowColours.name,
    );
  }
}

final captionAppearanceStoreProvider = Provider<CaptionAppearanceStore>(
  (ref) => CaptionAppearanceStore(ref.watch(preferencesProvider)),
);
