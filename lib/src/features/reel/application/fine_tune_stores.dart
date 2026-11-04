import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/reel/data/fine_tune_draft_store.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// The two stores a kept fine-tune needs: its own, and the scripts it points
/// at. Opened on first use so building a service costs nothing.
typedef FineTuneStores = ({
  Future<FineTuneDraftStore> Function() drafts,
  Future<TranscriptStore> Function() scripts,
});

final fineTuneStoresProvider = Provider<FineTuneStores>(
  (ref) => (
    drafts: () => ref.read(fineTuneDraftStoreProvider.future),
    scripts: () => ref.read(transcriptStoreProvider.future),
  ),
);
