import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_stores.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';

/// Stands in for `savedAt` when two drafts are compared by their work alone.
final _noTime = DateTime.utc(1970);

/// Keeps the fine-tune on disk as it changes, so it can be continued later
/// (spec FR-24). All work runs one after another, so a delete after an export
/// never loses to a save that was still writing.
class FineTuneDraftSaver {
  FineTuneDraftSaver({
    required this.stores,
    required this.onChanged,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FineTuneStores stores;
  final void Function() onChanged;
  final DateTime Function() _clock;

  Future<void> _tail = Future<void>.value();
  FineTuneDraft? _lastWritten;
  FineTuneDraft? _lastDiscarded;

  /// Writes [draft] unless it can't be kept yet or is the work already kept
  /// (or already exported). A failed write is ignored: the work is still in
  /// the app, and the next change writes again.
  Future<void> save(ReelDraft draft) {
    if (!FineTuneDraft.canKeep(draft)) {
      return Future<void>.value();
    }
    return _enqueue(() => _write(draft));
  }

  /// Deletes the kept fine-tune of [draft] (it was exported), and stops the
  /// same work being kept again.
  Future<void> discard(ReelDraft draft) {
    if (!FineTuneDraft.canKeep(draft)) {
      return Future<void>.value();
    }
    return _enqueue(() => _delete(draft));
  }

  /// Notes that [draft] is already kept on disk as it is (it was just
  /// continued), so leaving Fine-tune without a change doesn't rewrite it.
  Future<void> rememberKept(ReelDraft draft) {
    if (!FineTuneDraft.canKeep(draft)) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      _lastWritten = FineTuneDraft.of(draft, savedAt: _noTime);
      _lastDiscarded = null;
    });
  }

  Future<void> _write(ReelDraft draft) async {
    final work = FineTuneDraft.of(draft, savedAt: _noTime);
    final store = await stores.drafts();
    // The file can be deleted elsewhere (Delete progress, a failed Continue),
    // so "already written" only counts while it is still there.
    final alreadyKept = work == _lastWritten && await store.has(work.script);
    if (alreadyKept || work == _lastDiscarded) {
      return;
    }
    final kept = FineTuneDraft.of(draft, savedAt: _clock());
    await store.save(kept);
    _lastWritten = work;
    _lastDiscarded = null;
    await (await stores.scripts()).markUsed(kept.script.videoId);
    onChanged();
  }

  Future<void> _delete(ReelDraft draft) async {
    final work = FineTuneDraft.of(draft, savedAt: _noTime);
    await (await stores.drafts()).delete(work.script);
    _lastWritten = null;
    _lastDiscarded = work;
    onChanged();
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final run = _tail.then((_) => _ignoringFailure(work));
    _tail = run;
    return run;
  }

  Future<void> _ignoringFailure(Future<void> Function() work) async {
    try {
      await work();
    } on Object {
      // An Error must not end the queue either: every later save would be
      // skipped for the rest of the session.
      return;
    }
  }
}

final fineTuneDraftSaverProvider = Provider<FineTuneDraftSaver>((ref) {
  return FineTuneDraftSaver(
    stores: ref.read(fineTuneStoresProvider),
    onChanged: () {
      if (ref.mounted) {
        ref.invalidate(fineTuneDraftsProvider);
      }
    },
  );
});
