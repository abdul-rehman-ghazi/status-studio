import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// Files written before M53: a session per topic and a topic's candidates
/// (without the transcript key before M50).
final _retiredFileName = RegExp(
  r'^(session_[0-9a-f]{16}|topic_[0-9a-f]{16}(_[0-9a-f]{12})?)\.json$',
);

/// A linked video's transcript in one output language (spec FR-44).
typedef SavedLinkScript = ({ScriptLanguage language, DateTime savedAt});

/// Transcripts, Review cuts sessions and the facts of linked videos, under
/// `topics/<YouTube ID>/` (spec FR-36, FR-38, FR-43), so the same link
/// again sends nothing to Groq. An unreadable file reads as missing.
class TopicStore {
  const TopicStore(this.root);

  final Directory root;

  /// The transcript in [language], or null when there is none yet (M50: a
  /// transcript in another language is never reused).
  Future<List<TranscriptBlock>?> savedBlocks(
    String youTubeId,
    ScriptLanguage language,
  ) async {
    final saved = await _readJson(_blocksFile(youTubeId, language));
    if (saved is! List<Object?>) {
      return null;
    }
    return [
      for (final block in saved)
        TranscriptBlock.fromJson(block! as Map<String, Object?>),
    ];
  }

  /// The output languages [youTubeId]'s transcript is saved in, each with
  /// when it was saved, for History (spec FR-44).
  Future<List<SavedLinkScript>> savedScripts(String youTubeId) async {
    final saved = <SavedLinkScript>[];
    for (final language in outputLanguages) {
      final file = _blocksFile(youTubeId, language);
      if (await file.exists()) {
        final savedAt = (await file.stat()).modified;
        saved.add((language: language, savedAt: savedAt));
      }
    }
    return saved;
  }

  Future<void> saveBlocks(
    String youTubeId,
    ScriptLanguage language,
    List<TranscriptBlock> blocks,
  ) => _writeJson(_blocksFile(youTubeId, language), [
    for (final block in blocks) block.toJson(),
  ]);

  /// Keeps [session] for Recent (spec FR-38), one per linked video
  /// (FR-43): a session in another output language replaces it.
  Future<void> saveSession(LinkSession session) => _writeJson(
    _sessionFile(session.request.video.videoId),
    session.toJson(),
  );

  /// Every readable session, newest first. An unreadable file is skipped
  /// and left on disk.
  Future<List<LinkSession>> sessions() async {
    final sessions = <LinkSession>[];
    for (final youTubeId in await videoIds()) {
      if (await session(youTubeId) case final session?) {
        sessions.add(session);
      }
    }
    sessions.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return sessions;
  }

  /// The session of [youTubeId], or null when there is none or it can't be
  /// read.
  Future<LinkSession?> session(String youTubeId) async {
    final saved = await _readJson(_sessionFile(youTubeId));
    if (saved is! Map<String, Object?>) {
      return null;
    }
    try {
      return LinkSession.fromJson(saved);
    } on FormatException {
      return null;
    }
  }

  Future<void> deleteSession(String youTubeId) async {
    final file = _sessionFile(youTubeId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Keeps what the link card read about [video] (spec FR-44): History
  /// shows it, and New opens Review cuts with it, after the session goes.
  Future<void> saveVideo(LinkedVideo video) =>
      _writeJson(_videoFile(video.videoId), video.toJson());

  /// Null when [youTubeId] was never opened on Review cuts since M53, or
  /// its file can't be read.
  Future<LinkedVideo?> savedVideo(String youTubeId) async {
    final saved = await _readJson(_videoFile(youTubeId));
    if (saved is! Map<String, Object?>) {
      return null;
    }
    try {
      return LinkedVideo.fromJson(saved);
    } on FormatException {
      return null;
    }
  }

  /// Every linked video with a folder here.
  Future<List<String>> videoIds() async {
    if (!await root.exists()) {
      return const [];
    }
    return [
      await for (final folder in root.list())
        if (folder is Directory) folder.path.split('/').last,
    ];
  }

  /// Deletes the sessions and topic candidates of before M53 (spec FR-43).
  /// Saved transcripts stay: they are the costly part. Cheap and harmless
  /// to repeat, so it runs at every start.
  Future<void> deleteRetired() async {
    for (final youTubeId in await videoIds()) {
      await for (final entry in Directory('${root.path}/$youTubeId').list()) {
        if (entry is File &&
            _retiredFileName.hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
    }
  }

  /// Removes what was last changed before [cutoff], like old scripts.
  Future<void> deleteOlderThan(DateTime cutoff) async {
    if (!await root.exists()) {
      return;
    }
    await for (final folder in root.list()) {
      if (folder is Directory &&
          (await folder.stat()).modified.isBefore(cutoff)) {
        await folder.delete(recursive: true);
      }
    }
  }

  /// `transcript.json`, written before M50 in whatever language the
  /// captions had, is no longer read; it goes with its folder's age.
  File _blocksFile(String youTubeId, ScriptLanguage language) =>
      File('${root.path}/$youTubeId/transcript_${language.whisperCode}.json');

  File _sessionFile(String youTubeId) =>
      File('${root.path}/$youTubeId/session.json');

  File _videoFile(String youTubeId) =>
      File('${root.path}/$youTubeId/video.json');

  Future<Object?> _readJson(File file) async {
    try {
      return jsonDecode(await file.readAsString());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Written beside and renamed, so a file is never half written.
  Future<void> _writeJson(File file, Object? json) async {
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsString(jsonEncode(json));
    await partial.rename(file.path);
  }
}

final topicStoreProvider = FutureProvider<TopicStore>((ref) async {
  final support = await getApplicationSupportDirectory();
  return TopicStore(Directory('${support.path}/topics'));
});
