import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/topic/domain/moment_candidate.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// A topic and the language its moments are written in (spec FR-36).
typedef TopicSearch = ({String topic, ScriptLanguage outputLanguage});

final _sessionFileName = RegExp(r'^session_[0-9a-f]{16}\.json$');

/// Transcripts, topic candidates and Review cuts sessions of linked videos,
/// under `topics/<YouTube ID>/` (spec FR-36, FR-38), so the same link or
/// topic again sends nothing to Groq. An unreadable file reads as missing.
class TopicStore {
  const TopicStore(this.root);

  final Directory root;

  Future<List<TranscriptBlock>?> savedBlocks(String youTubeId) async {
    final saved = await _readJson(_blocksFile(youTubeId));
    if (saved is! List<Object?>) {
      return null;
    }
    return [
      for (final block in saved)
        TranscriptBlock.fromJson(block! as Map<String, Object?>),
    ];
  }

  Future<void> saveBlocks(String youTubeId, List<TranscriptBlock> blocks) =>
      _writeJson(_blocksFile(youTubeId), [
        for (final block in blocks) block.toJson(),
      ]);

  /// Every moment Groq found for [search], or null when it wasn't asked yet.
  Future<List<MomentCandidate>?> savedCandidates(
    String youTubeId,
    TopicSearch search,
  ) async {
    final saved = await _readJson(_candidatesFile(youTubeId, search));
    if (saved is! Map<String, Object?>) {
      return null;
    }
    return [
      for (final candidate in saved['candidates']! as List<Object?>)
        MomentCandidate.fromJson(candidate! as Map<String, Object?>),
    ];
  }

  Future<void> saveCandidates(
    String youTubeId,
    TopicSearch search,
    List<MomentCandidate> candidates,
  ) => _writeJson(_candidatesFile(youTubeId, search), {
    'candidates': [for (final candidate in candidates) candidate.toJson()],
  });

  /// Keeps [session] for Recent (spec FR-38), one per video and search.
  Future<void> saveSession(LinkSession session) =>
      _writeJson(_sessionFile(session.request), session.toJson());

  /// Every readable session, newest first. An unreadable file is skipped
  /// and left on disk.
  Future<List<LinkSession>> sessions() async {
    if (!await root.exists()) {
      return const [];
    }
    final sessions = <LinkSession>[];
    await for (final folder in root.list()) {
      if (folder is Directory) {
        sessions.addAll(await _sessionsIn(folder));
      }
    }
    sessions.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return sessions;
  }

  Future<void> deleteSession(TopicRequest request) async {
    final file = _sessionFile(request);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<LinkSession>> _sessionsIn(Directory folder) async {
    final sessions = <LinkSession>[];
    await for (final entry in folder.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is! File || !_sessionFileName.hasMatch(name)) {
        continue;
      }
      if (await _readSession(entry) case final session?) {
        sessions.add(session);
      }
    }
    return sessions;
  }

  Future<LinkSession?> _readSession(File file) async {
    final saved = await _readJson(file);
    if (saved is! Map<String, Object?>) {
      return null;
    }
    try {
      return LinkSession.fromJson(saved);
    } on FormatException {
      return null;
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

  File _blocksFile(String youTubeId) =>
      File('${root.path}/$youTubeId/transcript.json');

  File _candidatesFile(String youTubeId, TopicSearch search) =>
      File('${root.path}/$youTubeId/topic_${_searchKey(search)}.json');

  File _sessionFile(TopicRequest request) {
    final search = (
      topic: request.topic,
      outputLanguage: request.outputLanguage,
    );
    final youTubeId = request.video.videoId;
    return File('${root.path}/$youTubeId/session_${_searchKey(search)}.json');
  }

  /// The same topic typed with other spacing or capitals is the same topic;
  /// another output language is another search.
  String _searchKey(TopicSearch search) {
    final normalised = '${search.outputLanguage.whisperCode}:${search.topic}'
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    return sha256.convert(utf8.encode(normalised)).toString().substring(0, 16);
  }

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
