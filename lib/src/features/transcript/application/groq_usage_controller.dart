import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/data/groq_usage_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_usage.dart';

/// The audio this phone sent to Groq with the saved key (spec FR-45).
final groqUsageProvider = AsyncNotifierProvider<GroqUsageController, GroqUsage>(
  GroqUsageController.new,
);

class GroqUsageController extends AsyncNotifier<GroqUsage>
    implements GroqUsageRecorder {
  GroqUsageStore get _store => ref.read(groqUsageStoreProvider);

  @override
  Future<GroqUsage> build() => _store.saved();

  @override
  Future<void> audioSent(Duration audio) async {
    final now = DateTime.now();
    final billed = audio < shortestBilledAudio ? shortestBilledAudio : audio;
    await _keep((await future).withSend(AudioSend(sentAt: now, audio: billed)));
  }

  @override
  Future<void> limitReached(Duration wait) async {
    await _keep((await future).blockedAfter(wait, DateTime.now()));
  }

  /// Another key has its own allowance, so it starts with nothing sent.
  Future<void> forget() async {
    state = const AsyncData(GroqUsage.none);
    await _store.forget();
  }

  Future<void> _keep(GroqUsage usage) async {
    state = AsyncData(usage);
    await _store.save(usage);
  }
}
