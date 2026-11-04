import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_query.dart';

LyricsCandidate song(
  String name,
  int seconds, {
  String lyrics = '[00:01.00] a',
}) => LyricsCandidate(
  trackName: name,
  length: Duration(seconds: seconds),
  syncedLyrics: lyrics,
);

const videoLength = Duration(seconds: 214);

void main() {
  test('closest_length_wins_among_named_songs', () {
    final best = bestLyricsFor(
      [
        song('Never Gonna Give You Up', 220),
        song('Never Gonna Give You Up', 215),
      ],
      videoTitle: 'Rick Astley - Never Gonna Give You Up',
      videoLength: videoLength,
    );

    expect(best.length, const Duration(seconds: 215));
  });

  test('song_much_longer_than_the_video_is_another_recording', () {
    expect(
      () => bestLyricsFor(
        [song('Never Gonna Give You Up', 260)],
        videoTitle: 'Never Gonna Give You Up',
        videoLength: videoLength,
      ),
      throwsA(isA<LyricsNotFoundException>()),
    );
  });

  test('song_not_named_in_the_video_title_is_skipped', () {
    expect(
      () => bestLyricsFor(
        [song('Completely Different Song', 214)],
        videoTitle: 'Never Gonna Give You Up',
        videoLength: videoLength,
      ),
      throwsA(isA<LyricsNotFoundException>()),
    );
  });

  test('song_with_only_plain_lyrics_is_skipped', () {
    expect(
      () => bestLyricsFor(
        [song('Never Gonna Give You Up', 214, lyrics: '')],
        videoTitle: 'Never Gonna Give You Up',
        videoLength: videoLength,
      ),
      throwsA(isA<LyricsNotFoundException>()),
    );
  });

  test('track_name_in_urdu_script_matches_the_title', () {
    final best = bestLyricsFor(
      [song('علم بڑی دولت ہے', 214)],
      videoTitle: 'علم بڑی دولت ہے | Naat',
      videoLength: videoLength,
    );

    expect(best.trackName, 'علم بڑی دولت ہے');
  });

  test('query_drops_brackets_noise_and_text_after_a_bar', () {
    expect(
      lyricsQueryFor(
        'Rick Astley - Never Gonna Give You Up (Official Video) [4K] | Remastered',
      ),
      'Rick Astley Never Gonna Give You Up',
    );
  });
}
