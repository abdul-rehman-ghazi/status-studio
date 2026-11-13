import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/topic/application/link_sessions_controller.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

/// Keeps Review cuts on disk as it changes, so it can be continued from
/// Recent (spec FR-38). All work runs one after another, so the delete after
/// Make the clip never loses to a save that was still writing.
class LinkSessionSaver {
  LinkSessionSaver({required this.store, required this.onChanged});

  final Future<TopicStore> Function() store;
  final void Function() onChanged;

  Future<void> _tail = Future<void>.value();

  /// A failed write is ignored: the cuts are still on screen, and the next
  /// change writes again.
  Future<void> save(LinkSession session) =>
      _enqueue(() async => (await store()).saveSession(session));

  /// The clip was made from [request], so its session is spent.
  Future<void> delete(TopicRequest request) =>
      _enqueue(() async => (await store()).deleteSession(request));

  Future<void> _enqueue(Future<void> Function() work) {
    final run = _tail.then((_) => _ignoringFailure(work));
    _tail = run;
    return run;
  }

  Future<void> _ignoringFailure(Future<void> Function() work) async {
    try {
      await work();
      onChanged();
    } on Object {
      // An Error must not end the queue either: every later save would be
      // skipped for the rest of the session.
      return;
    }
  }
}

final linkSessionSaverProvider = Provider<LinkSessionSaver>((ref) {
  return LinkSessionSaver(
    store: () => ref.read(topicStoreProvider.future),
    onChanged: () {
      if (ref.mounted) {
        ref.invalidate(linkSessionsProvider);
      }
    },
  );
});
