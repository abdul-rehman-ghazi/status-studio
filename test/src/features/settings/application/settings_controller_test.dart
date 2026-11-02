import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/settings/application/settings_controller.dart';
import 'package:status_studio/src/features/transcript/application/real_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';

void main() {
  test('chosen_model_reaches_whisper', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final container = ProviderContainer.test();
    container.listen(whisperModelProvider, (_, _) {});
    await container.read(whisperModelSettingProvider.future);

    await container
        .read(whisperModelSettingProvider.notifier)
        .select(SpeechModel.base);

    expect(container.read(whisperModelProvider), SpeechModel.base);
  });

  test('stored_choice_is_used_after_restart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'settings.whisperModel': 'base',
        });
    final container = ProviderContainer.test();
    container.listen(whisperModelProvider, (_, _) {});

    await container.read(whisperModelSettingProvider.future);

    expect(container.read(whisperModelProvider), SpeechModel.base);
  });
}
