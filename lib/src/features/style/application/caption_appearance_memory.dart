import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/style/data/caption_appearance_store.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';

/// The appearance saved when the app started. `main` reads it and overrides
/// this, so the first new reel already starts from it (spec FR-7).
final savedCaptionAppearanceProvider = Provider<CaptionAppearance>(
  (ref) => const CaptionAppearance(),
);

/// The caption appearance used last; a new reel starts from it.
class CaptionAppearanceMemory extends Notifier<CaptionAppearance> {
  @override
  CaptionAppearance build() => ref.watch(savedCaptionAppearanceProvider);

  void remember(CaptionAppearance appearance) {
    if (appearance == state) {
      return;
    }
    state = appearance;
    unawaited(_save(appearance));
  }

  Future<void> _save(CaptionAppearance appearance) async {
    try {
      await ref.read(captionAppearanceStoreProvider).save(appearance);
    } on Object {
      // Only the next new reel's starting look depends on it; the reel in
      // hand already has the appearance.
    }
  }
}

final captionAppearanceMemoryProvider =
    NotifierProvider<CaptionAppearanceMemory, CaptionAppearance>(
      CaptionAppearanceMemory.new,
    );
