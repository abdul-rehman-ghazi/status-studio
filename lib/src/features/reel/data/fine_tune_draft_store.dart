import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/json_files.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft_json.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

final _draftFileName = RegExp(r'^draft-([^-.]+)\.json$');

/// Kept fine-tunes beside the saved scripts, as
/// `transcripts/<videoId>/draft-<language>.json` (spec FR-24). They go with
/// the video's folder when the scripts are pruned.
class FineTuneDraftStore {
  FineTuneDraftStore(this.root);

  final Directory root;

  Future<void> save(FineTuneDraft draft) =>
      writeJsonAtomically(_file(draft.script), fineTuneDraftToJson(draft));

  /// Every readable draft, newest first. A file that can't be read, comes
  /// from a newer version or sits in the wrong place is skipped and left on
  /// disk.
  Future<List<FineTuneDraft>> list() async {
    if (!await root.exists()) {
      return const [];
    }
    final drafts = <FineTuneDraft>[];
    await for (final entry in root.list()) {
      if (entry is Directory) {
        drafts.addAll(await _draftsIn(entry));
      }
    }
    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  /// Whether a file is kept for [key], readable or not.
  Future<bool> has(TranscriptKey key) => _file(key).exists();

  Future<void> delete(TranscriptKey key) async {
    final file = _file(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  File _file(TranscriptKey key) => File(
    '${root.path}/${key.videoId}/draft-${key.language.whisperCode}.json',
  );

  /// A draft counts only in its own place: the folder and file name must
  /// say what the draft says.
  Future<List<FineTuneDraft>> _draftsIn(Directory folder) async {
    final drafts = <FineTuneDraft>[];
    await for (final entry in folder.list()) {
      final draft = entry is File ? await _readDraft(entry) : null;
      if (draft != null && _file(draft.script).path == entry.path) {
        drafts.add(draft);
      }
    }
    return drafts;
  }

  /// The draft in [file], or `null` when [file] isn't a readable draft.
  Future<FineTuneDraft?> _readDraft(File file) async {
    final name = file.uri.pathSegments.last;
    if (!_draftFileName.hasMatch(name)) {
      return null;
    }
    try {
      return fineTuneDraftFromJson(await readJsonObject(file));
    } on Exception {
      return null;
    }
  }
}

final fineTuneDraftStoreProvider = FutureProvider<FineTuneDraftStore>((
  ref,
) async {
  final scripts = await ref.watch(transcriptStoreProvider.future);
  return FineTuneDraftStore(scripts.root);
});
