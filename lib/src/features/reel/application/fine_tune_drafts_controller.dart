import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_stores.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// The kept fine-tunes for Recent (spec FR-11, FR-24), newest first. A draft
/// whose video details are gone isn't listed: there'd be no title to show.
final fineTuneDraftsProvider =
    AsyncNotifierProvider<FineTuneDraftsController, List<SavedFineTune>>(
      FineTuneDraftsController.new,
    );

class FineTuneDraftsController extends AsyncNotifier<List<SavedFineTune>> {
  @override
  Future<List<SavedFineTune>> build() async {
    final stores = ref.watch(fineTuneStoresProvider);
    final drafts = await (await stores.drafts()).list();
    final scripts = await stores.scripts();
    final listed = <SavedFineTune>[];
    for (final draft in drafts) {
      try {
        final video = await scripts.loadVideo(draft.videoId);
        listed.add(SavedFineTune(video: video, draft: draft));
      } on NoSavedVideoException {
        continue;
      }
    }
    return listed;
  }

  /// Deletes the kept fine-tune only; the video's script stays.
  Future<void> delete(SavedFineTune saved) async {
    final stores = ref.read(fineTuneStoresProvider);
    await (await stores.drafts()).delete(saved.draft.videoId);
    ref.invalidateSelf();
    await future;
  }
}
