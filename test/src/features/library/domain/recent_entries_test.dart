import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/library/domain/recent_entries.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import '../../../../helpers/fine_tune_drafts.dart';

DateTime _day(int day) => DateTime.utc(2026, 11, day);

SavedScript _script({
  String videoId = 'abc123',
  ScriptLanguage language = ScriptLanguage.urdu,
  int day = 1,
}) {
  return SavedScript(
    video: SourceVideo(
      videoId: videoId,
      title: 'A song',
      channel: 'A channel',
      duration: const Duration(minutes: 3),
    ),
    language: language,
    saved: SavedTranscript(
      transcript: const Transcript(languageCode: 'ur', lines: []),
      source: captionsSource,
      savedAt: _day(day),
    ),
  );
}

RecentReel _reel({required int day}) => RecentReel(
  id: 'reel-$day',
  title: 'A reel',
  videoPath: '/reel.mp4',
  thumbnailPath: '/reel.jpg',
  duration: const Duration(seconds: 20),
  size: const OutputSize(1080, 1920),
  createdAt: _day(day),
);

void main() {
  test('a_fine_tune_replaces_its_script_row', () {
    final entries = recentEntries(
      reels: const [],
      scripts: [_script()],
      fineTunes: [savedFineTune(savedAt: _day(2))],
    );

    expect(entries.single, isA<FineTuneEntry>());
  });

  test('a_script_in_another_language_keeps_its_row', () {
    final entries = recentEntries(
      reels: const [],
      scripts: [_script(language: ScriptLanguage.auto)],
      fineTunes: [savedFineTune(savedAt: _day(2))],
    );

    expect(entries.map((entry) => entry.runtimeType), [
      FineTuneEntry,
      ScriptEntry,
    ]);
  });

  test('entries_are_sorted_newest_first', () {
    final entries = recentEntries(
      reels: [_reel(day: 3)],
      scripts: [_script(videoId: 'other')],
      fineTunes: [savedFineTune(savedAt: _day(2))],
    );

    expect(entries.map((entry) => entry.runtimeType), [
      ReelEntry,
      FineTuneEntry,
      ScriptEntry,
    ]);
  });

  test('a_fine_tune_is_dated_by_its_last_save', () {
    final entries = recentEntries(
      reels: const [],
      scripts: [_script()],
      fineTunes: [savedFineTune(savedAt: _day(5))],
    );

    expect(entries.single.sortedAt, _day(5));
  });

  test('a_fine_tune_without_a_script_row_is_still_listed', () {
    final entries = recentEntries(
      reels: const [],
      scripts: const [],
      fineTunes: [savedFineTune(savedAt: _day(2))],
    );

    expect(entries.single, isA<FineTuneEntry>());
  });
}
