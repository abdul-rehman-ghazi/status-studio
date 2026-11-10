import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/appearance/data/theme_choice_store.dart';
import 'package:status_studio/src/features/appearance/domain/theme_choice.dart';

/// The choice saved when the app started. `main` reads it before the first
/// frame and overrides this, so no frame is drawn in the wrong theme
/// (spec FR-32).
final savedThemeChoiceProvider = Provider<ThemeChoice>(
  (ref) => ThemeChoice.system,
);

/// The theme in use; a new choice applies at once and is saved.
class ThemeChoiceController extends Notifier<ThemeChoice> {
  @override
  ThemeChoice build() => ref.watch(savedThemeChoiceProvider);

  Future<void> choose(ThemeChoice choice) async {
    state = choice;
    await ref.read(themeChoiceStoreProvider).save(choice);
  }
}

final themeChoiceProvider =
    NotifierProvider<ThemeChoiceController, ThemeChoice>(
      ThemeChoiceController.new,
    );
