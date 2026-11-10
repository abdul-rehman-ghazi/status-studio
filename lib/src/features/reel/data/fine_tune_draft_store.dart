import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/json_files.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft_json.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

const _draftFileName = 'draft.json';

/// Version 1 kept one draft per video and language (M21–M29).
final _languageDraftFileName = RegExp(r'^draft-([^-.]+)\.json$');

/// Kept fine-tunes beside the saved scripts, one per video, as
/// `transcripts/<videoId>/draft.json` (spec FR-24, M30). They go with the
/// video's folder when the scripts are pruned.
class FineTuneDraftStore {
  FineTuneDraftStore(this.root);

  final Directory root;

  /// Writes [draft] and drops any version 1 drafts of its video, which it
  /// replaces.
  Future<void> save(FineTuneDraft draft) async {
    await writeJsonAtomically(_file(draft.videoId), fineTuneDraftToJson(draft));
    await _deleteLanguageDrafts(_folder(draft.videoId));
  }

  /// Every readable draft, newest first. A file that can't be read, comes
  /// from a newer version or sits in the wrong place is skipped and left on
  /// disk.
  Future<List<FineTuneDraft>> list() async {
    if (!await root.exists()) {
      return const [];
    }
    final drafts = <FineTuneDraft>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) {
        continue;
      }
      if (await _draftIn(entry) case final draft?) {
        drafts.add(draft);
      }
    }
    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  /// Whether a draft file is kept for [videoId], readable or not.
  Future<bool> has(String videoId) async {
    if (await _file(videoId).exists()) {
      return true;
    }
    return (await _languageDraftFiles(_folder(videoId))).isNotEmpty;
  }

  Future<void> delete(String videoId) async {
    final file = _file(videoId);
    if (await file.exists()) {
      await file.delete();
    }
    await _deleteLanguageDrafts(_folder(videoId));
  }

  Directory _folder(String videoId) => Directory('${root.path}/$videoId');

  File _file(String videoId) =>
      File('${_folder(videoId).path}/$_draftFileName');

  /// The video's draft: `draft.json`, or else the newest version 1 draft,
  /// whose older siblings are deleted (one draft per video since M30).
  Future<FineTuneDraft?> _draftIn(Directory folder) async {
    final videoId = folder.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final current = await _readDraft(_file(videoId), videoId);
    if (current != null) {
      return current;
    }
    final older = <(File, FineTuneDraft)>[];
    for (final file in await _languageDraftFiles(folder)) {
      if (await _readDraft(file, videoId) case final draft?) {
        older.add((file, draft));
      }
    }
    if (older.isEmpty) {
      return null;
    }
    final newest = older.reduce(
      (a, b) => a.$2.savedAt.isAfter(b.$2.savedAt) ? a : b,
    );
    await _deleteLanguageDrafts(folder, keep: newest.$1);
    return newest.$2;
  }

  Future<List<File>> _languageDraftFiles(Directory folder) async {
    if (!await folder.exists()) {
      return const [];
    }
    final files = <File>[];
    await for (final entry in folder.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && _languageDraftFileName.hasMatch(name)) {
        files.add(entry);
      }
    }
    return files;
  }

  Future<void> _deleteLanguageDrafts(Directory folder, {File? keep}) async {
    for (final file in await _languageDraftFiles(folder)) {
      if (file.path != keep?.path) {
        await file.delete();
      }
    }
  }

  /// The draft in [file], or `null` when it isn't a readable draft of
  /// [videoId]: a draft counts only in its own video's folder.
  Future<FineTuneDraft?> _readDraft(File file, String videoId) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final draft = fineTuneDraftFromJson(await readJsonObject(file));
      return draft.videoId == videoId ? draft : null;
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
