import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/preferences.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';

const _modelKey = 'settings.whisperModel';

/// The speech model Whisper uses (spec FR-12): small unless changed.
final whisperModelSettingProvider =
    AsyncNotifierProvider<SettingsController, SpeechModel>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<SpeechModel> {
  @override
  Future<SpeechModel> build() async {
    final stored = await ref.read(preferencesProvider).getString(_modelKey);
    return SpeechModel.values
            .where((model) => model.name == stored)
            .firstOrNull ??
        defaultSpeechModel;
  }

  /// Only the choice changes; downloaded models stay until deleted. The
  /// choice is stored first, so a failed write doesn't show a choice that
  /// is lost on restart.
  Future<void> select(SpeechModel model) async {
    await ref.read(preferencesProvider).setString(_modelKey, model.name);
    state = AsyncData(model);
  }
}

/// Bytes of [SpeechModel] on the phone; 0 when it isn't downloaded.
final modelSizeProvider = FutureProvider.autoDispose.family<int, SpeechModel>(
  (ref, model) => ref.watch(modelManagerProvider).sizeOnDisk(model),
);

/// Bytes kept from a paused download of [SpeechModel]; 0 when there are
/// none.
final modelPartialSizeProvider = FutureProvider.autoDispose
    .family<int, SpeechModel>(
      (ref, model) => ref.watch(modelManagerProvider).partialSize(model),
    );
