import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

const _keepUnused = Duration(days: 90);
const _maximumVideos = 200;
const _lastUsedFile = 'last_used';
const _videoFile = 'video.json';
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
    final saved = await _savedScripts(key);
    if (saved.isEmpty) {
      throw const NoSavedTranscriptException();
    }
    await _touch(key.videoId);
    return _newest(saved);
  }

  Future<void> save(TranscriptKey key, SavedTranscript saved) async {
    await _write(_scriptFile(key, saved.source), saved.toJson());
    await _touch(key.videoId);
  }

  /// Keeps [video]'s title, channel and length beside its scripts, so the
  /// Recent list can show and reopen them (FR-11).
  Future<void> saveVideo(SourceVideo video) => _write(
    File('${_folder(video.videoId).path}/$_videoFile'),
    video.toJson(),
  );

  /// Every finished script whose video was saved, newest first: one per
  /// video and requested language, from its newest source. Doesn't count
  /// as a use.
  Future<List<SavedScript>> list() async {
    if (!await root.exists()) {
      return const [];
    }
    final scripts = <SavedScript>[];
    await for (final folder in root.list().where((e) => e is Directory)) {
      scripts.addAll(await _scriptsIn(folder as Directory));
    }
    scripts.sort((a, b) => b.saved.savedAt.compareTo(a.saved.savedAt));
    return scripts;
  }

  /// Removes [key]'s scripts and unfinished progress; the video's other
  /// languages stay.
  Future<void> delete(TranscriptKey key) async {
    for (final file in await _languageFiles(key)) {
      await file.delete();
    }
  }

  Future<PartialTranscript> loadPartial(
    TranscriptKey key,
    String source,
  ) async {
    try {
      final json = await _readJson(_partialFile(key, source));
      return PartialTranscript.fromJson(json);
    } on Exception {
      throw const NoSavedTranscriptException();
    }
  }

  Future<void> savePartial(
    TranscriptKey key,
    String source,
    PartialTranscript partial,
  ) async {
    await _write(_partialFile(key, source), partial.toJson());
    // Counts as a use, or pruning would drop progress the user can resume.
    await _touch(key.videoId);
  }

  Future<void> clearPartial(TranscriptKey key, String source) async {
    final file = _partialFile(key, source);
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

  SavedTranscript _newest(List<SavedTranscript> saved) =>
      saved.reduce((a, b) => b.savedAt.isAfter(a.savedAt) ? b : a);

  Directory _folder(String videoId) => Directory('${root.path}/$videoId');

  File _scriptFile(TranscriptKey key, String source) => File(
    '${_folder(key.videoId).path}/${key.language.whisperCode}-$source.json',
  );

  File _partialFile(TranscriptKey key, String source) => File(
    '${_folder(key.videoId).path}/'
    '${key.language.whisperCode}-$source$_partialSuffix',
  );

  /// [folder]'s scripts, or none when its video can't be read: scripts
  /// saved before videos were kept have no title to show.
  Future<List<SavedScript>> _scriptsIn(Directory folder) async {
    final SourceVideo video;
    try {
      video = SourceVideo.fromJson(
        await _readJson(File('${folder.path}/$_videoFile')),
      );
    } on Exception {
      return const [];
    }
    final scripts = <SavedScript>[];
    for (final language in ScriptLanguage.values) {
      final key = TranscriptKey(videoId: video.videoId, language: language);
      final saved = await _savedScripts(key);
      if (saved.isNotEmpty) {
        scripts.add(
          SavedScript(video: video, language: language, saved: _newest(saved)),
        );
      }
    }
    return scripts;
  }

  /// [key]'s readable scripts, one per source.
  Future<List<SavedTranscript>> _savedScripts(TranscriptKey key) async {
    final saved = <SavedTranscript>[];
    for (final file in await _scriptFiles(key)) {
      saved.addAll(await _readScript(file));
    }
    return saved;
  }

  Future<List<File>> _scriptFiles(TranscriptKey key) async {
    final files = await _languageFiles(key);
    return files
        .where(
          (file) =>
              file.path.endsWith('.json') &&
              !file.path.endsWith(_partialSuffix),
        )
        .toList();
  }

  /// Everything saved for [key]'s language: scripts, progress and any
  /// half-written `.part` file.
  Future<List<File>> _languageFiles(TranscriptKey key) async {
    final folder = _folder(key.videoId);
    if (!await folder.exists()) {
      return const [];
    }
    final prefix = '${folder.path}/${key.language.whisperCode}-';
    final entries = await folder.list().toList();
    return entries
        .whereType<File>()
        .where((file) => file.path.startsWith(prefix))
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
