import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// Opens the Groq key screen from a "needs a free Groq key" failure and tells
/// whether a key is saved on the way back, so the failure can carry on
/// instead of staying on screen (spec §8, M67).
Future<bool> keySavedAfterGroqSettings(
  BuildContext context,
  WidgetRef ref,
) async {
  await context.push(AppRoutes.groqSettings);
  if (!context.mounted) {
    return false;
  }
  return ref.read(groqKeyStoreProvider).hasKey();
}
