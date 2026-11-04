import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/lyrics/data/lrclib_client.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_query.dart';
import 'package:status_studio/src/features/lyrics/domain/synced_lyrics.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/language_inference.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Replaces a video's script with its published lyrics (spec FR-17).
class LyricsService {
  LyricsService({
    required this.client,
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LrclibClient client;
  final Future<TranscriptStore> store;
  final DateTime Function() _clock;

  /// The video's lyrics as a script, saved so the video opens with them
  /// next time. Throws [LyricsNotFoundException] when no matching song has
  /// synced lyrics, and `OfflineException` when LRCLIB can't be reached.
  Future<Transcript> replaceScript(
    SourceVideo video,
    ScriptLanguage language,
  ) async {
    final candidates = await client.search(lyricsQueryFor(video.title));
    final song = bestLyricsFor(
      candidates,
      videoTitle: video.title,
      videoLength: video.duration,
    );
    final lines = parseSyncedLyrics(
      song.syncedLyrics,
      trackLength: video.duration,
    );
    if (lines.isEmpty) {
      throw const LyricsNotFoundException();
    }
    final transcript = Transcript(
      languageCode: inferLanguageCode(lines.map((line) => line.text).join(' ')),
      lines: lines,
    );
    await (await store).save(
      TranscriptKey(videoId: video.videoId, language: language),
      SavedTranscript(
        transcript: transcript,
        source: lyricsSource,
        savedAt: _clock(),
      ),
    );
    return transcript;
  }
}

final lyricsServiceProvider = Provider<LyricsService>(
  (ref) => LyricsService(
    client: LrclibClient(),
    store: ref.watch(transcriptStoreProvider.future),
  ),
);
