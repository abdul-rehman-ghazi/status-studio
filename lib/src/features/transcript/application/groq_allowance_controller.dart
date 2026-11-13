import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/data/groq_allowance_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_allowance.dart';

/// Groq's last reported audio allowance, `null` before the first script
/// piece with the saved key (spec FR-45).
final groqAllowanceProvider =
    AsyncNotifierProvider<GroqAllowanceController, GroqAllowance?>(
      GroqAllowanceController.new,
    );

class GroqAllowanceController extends AsyncNotifier<GroqAllowance?> {
  GroqAllowanceStore get _store => ref.read(groqAllowanceStoreProvider);

  @override
  Future<GroqAllowance?> build() => _store.saved();

  void record(GroqAllowance allowance) {
    state = AsyncData(allowance);
    unawaited(_store.save(allowance));
  }

  /// A key has its own allowance, so another key starts with none.
  Future<void> forget() async {
    state = const AsyncData(null);
    await _store.forget();
  }
}
