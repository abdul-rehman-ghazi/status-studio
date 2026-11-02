import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final stored = await SharedPreferencesAsync().getString(_modelKey);
    return SpeechModel.values
            .where((model) => model.name == stored)
            .firstOrNull ??
        SpeechModel.small;
  }

  /// Only the choice changes; downloaded models stay until deleted.
  Future<void> select(SpeechModel model) async {
    state = AsyncData(model);
    await SharedPreferencesAsync().setString(_modelKey, model.name);
  }
}

/// Bytes of [SpeechModel] on the phone; 0 when it isn't downloaded.
final modelSizeProvider = FutureProvider.autoDispose.family<int, SpeechModel>(
  (ref, model) => ref.watch(modelManagerProvider).sizeOnDisk(model),
);
