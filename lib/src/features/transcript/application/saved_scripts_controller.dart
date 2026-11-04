import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

/// Finished scripts in the Recent list on Home (FR-11), newest first, so a
/// processed video can be reopened before any reel is made from it.
final savedScriptsProvider =
    AsyncNotifierProvider<SavedScriptsController, List<SavedScript>>(
      SavedScriptsController.new,
    );

class SavedScriptsController extends AsyncNotifier<List<SavedScript>> {
  @override
  Future<List<SavedScript>> build() async {
    // The pipeline saves a script before reporting it done, so the list
    // read after that already has it.
    ref.listen(
      scriptProgressProvider.select(
        (run) => run.value?.stage == ScriptStage.done,
      ),
      (wasDone, isDone) {
        if (isDone) {
          ref.invalidateSelf();
        }
      },
    );
    final store = await ref.watch(transcriptStoreProvider.future);
    return store.list();
  }

  /// Forgets [script], so its link writes the script again next time.
  Future<void> delete(SavedScript script) async {
    final store = await ref.read(transcriptStoreProvider.future);
    await store.delete(script.key);
    ref.invalidateSelf();
  }
}
