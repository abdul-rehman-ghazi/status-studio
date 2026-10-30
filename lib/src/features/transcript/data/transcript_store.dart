import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

const _keepUnused = Duration(days: 90);
const _maximumVideos = 200;
const _lastUsedFile = 'last_used';
const _partialSuffix = '.partial.json';

/// Saved scripts and Whisper progress under `transcripts/<videoId>/`
/// (FR-14). Files are written as `.part` and renamed, so a crash never
/// leaves a half-written script that looks whole.
class TranscriptStore {
  TranscriptStore(this.root, {required this.clock});

  final Directory root;
  final DateTime Function() clock;

  /// The newest script saved for [key], from any source. Counts as a use.
  Future<SavedTranscript> load(TranscriptKey key) async {
    final saved = <SavedTranscript>[];
    for (final file in await _scriptFiles(key)) {
      saved.addAll(await _readScript(file));
    }
    if (saved.isEmpty) {
      throw const NoSavedTranscriptException();
    }
    await _touch(key.videoId);
    return saved.reduce((a, b) => b.savedAt.isAfter(a.savedAt) ? b : a);
  }

  Future<void> save(TranscriptKey key, SavedTranscript saved) async {
    await _write(_scriptFile(key, saved.source), saved.toJson());
    await _touch(key.videoId);
  }

  Future<PartialTranscript> loadPartial(
    TranscriptKey key,
    SpeechModel model,
  ) async {
    try {
      final json = await _readJson(_partialFile(key, model));
      return PartialTranscript.fromJson(json);
    } on Exception {
      throw const NoSavedTranscriptException();
    }
  }

  Future<void> savePartial(
    TranscriptKey key,
    SpeechModel model,
    PartialTranscript partial,
  ) async {
    await _write(_partialFile(key, model), partial.toJson());
    // Counts as a use, or pruning would drop progress the user can resume.
    await _touch(key.videoId);
  }

  Future<void> clearPartial(TranscriptKey key, SpeechModel model) async {
    final file = _partialFile(key, model);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Removes videos unused for 90 days, then the least recently used beyond
  /// 200. Returns how many videos were removed.
  Future<int> prune() async {
    if (!await root.exists()) {
      return 0;
    }
    final videos = <({Directory folder, DateTime lastUsed})>[];
    await for (final folder in root.list().where((e) => e is Directory)) {
      final directory = folder as Directory;
      videos.add((folder: directory, lastUsed: await _lastUsed(directory)));
    }
    videos.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    final cutoff = clock().subtract(_keepUnused);
    final removed = [
      for (final (rank, video) in videos.indexed)
        if (rank >= _maximumVideos || video.lastUsed.isBefore(cutoff))
          video.folder,
    ];
    for (final folder in removed) {
      await folder.delete(recursive: true);
    }
    return removed.length;
  }

  Directory _folder(String videoId) => Directory('${root.path}/$videoId');

  File _scriptFile(TranscriptKey key, String source) => File(
    '${_folder(key.videoId).path}/${key.language.whisperCode}-$source.json',
  );

  File _partialFile(TranscriptKey key, SpeechModel model) => File(
    '${_folder(key.videoId).path}/'
    '${key.language.whisperCode}-${whisperSource(model)}$_partialSuffix',
  );

  Future<List<File>> _scriptFiles(TranscriptKey key) async {
    final folder = _folder(key.videoId);
    if (!await folder.exists()) {
      return const [];
    }
    final prefix = '${folder.path}/${key.language.whisperCode}-';
    final entries = await folder.list().toList();
    return entries
        .whereType<File>()
        .where(
          (file) =>
              file.path.startsWith(prefix) &&
              file.path.endsWith('.json') &&
              !file.path.endsWith(_partialSuffix),
        )
        .toList();
  }

  /// The script in [file], or nothing when it's unreadable: a damaged file
  /// counts as missing rather than breaking the app.
  Future<List<SavedTranscript>> _readScript(File file) async {
    try {
      return [SavedTranscript.fromJson(await _readJson(file))];
    } on Exception {
      return const [];
    }
  }

  Future<Map<String, Object?>> _readJson(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    throw const FormatException('Not a JSON object.');
  }

  Future<void> _write(File target, Map<String, Object?> json) async {
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    await part.writeAsString(jsonEncode(json), flush: true);
    await part.rename(target.path);
  }

  Future<void> _touch(String videoId) =>
      File('${_folder(videoId).path}/$_lastUsedFile')
          .writeAsString(clock().toUtc().toIso8601String());

  /// A folder without a readable last-used time counts as never used.
  Future<DateTime> _lastUsed(Directory folder) async {
    try {
      final text = await File('${folder.path}/$_lastUsedFile').readAsString();
      return DateTime.parse(text);
    } on Exception {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }
}

final transcriptStoreProvider = FutureProvider<TranscriptStore>((ref) async {
  final support = await getApplicationSupportDirectory();
  return TranscriptStore(
    Directory('${support.path}/transcripts'),
    clock: DateTime.now,
  );
});
