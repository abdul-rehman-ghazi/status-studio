import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/youtube_link.dart';

const videoId = 'dQw4w9WgXcQ';

void main() {
  test('parses_watch_link', () {
    final parsed = parseYouTubeVideoId(
      'https://www.youtube.com/watch?v=$videoId',
    );

    expect(parsed, videoId);
  });

  test('parses_short_link', () {
    expect(parseYouTubeVideoId('https://youtu.be/$videoId'), videoId);
  });

  test('parses_shorts_link', () {
    expect(parseYouTubeVideoId('youtube.com/shorts/$videoId'), videoId);
  });

  test('parses_live_link', () {
    final parsed = parseYouTubeVideoId('https://www.youtube.com/live/$videoId');

    expect(parsed, videoId);
  });

  test('parses_mobile_link_with_share_params', () {
    final parsed = parseYouTubeVideoId(
      'https://m.youtube.com/watch?si=abc&v=$videoId&t=42',
    );

    expect(parsed, videoId);
  });

  test('parses_link_with_surrounding_whitespace', () {
    final parsed = parseYouTubeVideoId('  https://youtu.be/$videoId?si=x \n');

    expect(parsed, videoId);
  });

  test('parses_link_without_scheme', () {
    expect(parseYouTubeVideoId('youtu.be/$videoId'), videoId);
  });

  test('rejects_non_youtube_link', () {
    expect(
      () => parseYouTubeVideoId('https://vimeo.com/123'),
      throwsA(isA<InvalidYouTubeLinkException>()),
    );
  });

  test('rejects_wrong_length_id', () {
    expect(
      () => parseYouTubeVideoId('https://youtu.be/abc'),
      throwsA(isA<InvalidYouTubeLinkException>()),
    );
  });

  test('rejects_watch_link_without_video_param', () {
    expect(
      () => parseYouTubeVideoId('https://www.youtube.com/watch?list=abc'),
      throwsA(isA<InvalidYouTubeLinkException>()),
    );
  });

  test('rejects_plain_text', () {
    expect(
      () => parseYouTubeVideoId('hello'),
      throwsA(isA<InvalidYouTubeLinkException>()),
    );
  });
}
