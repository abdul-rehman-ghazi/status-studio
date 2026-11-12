import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/features/topic/domain/moment_candidate.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// Transcripts and topic candidates of linked videos, under
/// `topics/<YouTube ID>/` (spec FR-36), so the same link or topic again
/// sends nothing to Groq. An unreadable file reads as missing.
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

  /// Every moment Groq found for [topic], or null when it wasn't asked yet.
  Future<List<MomentCandidate>?> savedCandidates(
    String youTubeId,
    String topic,
  ) async {
    final saved = await _readJson(_candidatesFile(youTubeId, topic));
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
    String topic,
    List<MomentCandidate> candidates,
  ) => _writeJson(_candidatesFile(youTubeId, topic), {
    'candidates': [for (final candidate in candidates) candidate.toJson()],
  });

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

  /// The same topic typed with other spacing or capitals is the same topic.
  File _candidatesFile(String youTubeId, String topic) {
    final normalised = topic.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final key = sha256
        .convert(utf8.encode(normalised))
        .toString()
        .substring(0, 16);
    return File('${root.path}/$youTubeId/topic_$key.json');
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
