import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';

/// Links left on Review cuts, for Recent (spec FR-11, FR-38), newest first.
final linkSessionsProvider =
    AsyncNotifierProvider<LinkSessionsController, List<LinkSession>>(
      LinkSessionsController.new,
    );

class LinkSessionsController extends AsyncNotifier<List<LinkSession>> {
  @override
  Future<List<LinkSession>> build() async {
    final store = await ref.watch(topicStoreProvider.future);
    return store.sessions();
  }

  /// Deletes the session only; the saved script stays, so the same link
  /// sends nothing to Groq.
  Future<void> delete(LinkSession session) async {
    final store = await ref.read(topicStoreProvider.future);
    await store.deleteSession(session.request.video.videoId);
    ref.invalidateSelf();
    await future;
  }
}
