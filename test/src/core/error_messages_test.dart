import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/translation_errors.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

void main() {
  test('maps_no_speech', () {
    expect(
      errorMessageFor(const NoSpeechFoundException()),
      'No speech found in this video.',
    );
  });

  test('maps_youtube_changed', () {
    expect(
      errorMessageFor(const YouTubeChangedException('x')),
      "Couldn't read this video from YouTube. Try again later.",
    );
  });

  test('maps_unreadable_video', () {
    expect(
      errorMessageFor(const VideoUnreadableException('no audio')),
      "Can't read this video.",
    );
  });

  test('maps_offline', () {
    expect(
      errorMessageFor(const OfflineException('x')),
      "You're offline. Connect and try again.",
    );
  });

  test('maps_unavailable', () {
    expect(
      errorMessageFor(const VideoUnavailableException('x')),
      "This video can't be downloaded.",
    );
  });

  test('maps_storage', () {
    expect(
      errorMessageFor(const InsufficientStorageException('x')),
      'Not enough space on your phone.',
    );
  });

  test('maps_render_failed', () {
    expect(
      errorMessageFor(const RenderFailedException('codec')),
      "Couldn't make the reel.",
    );
  });

  test('maps_translation_pack_missing', () {
    expect(
      errorMessageFor(const TranslationPackMissingException('ur')),
      'English needs a one-time download.',
    );
  });

  test('maps_missing_groq_key', () {
    expect(
      errorMessageFor(const NoGroqKeyException()),
      'Writing a script needs a free Groq key.',
    );
  });

  test('maps_groq_key_rejected', () {
    expect(
      errorMessageFor(const GroqKeyRejectedException()),
      "Groq didn't accept your API key.",
    );
  });

  test('maps_groq_rate_limit_to_minutes_rounded_up', () {
    expect(
      errorMessageFor(const GroqRateLimitedException(Duration(seconds: 250))),
      "Groq's free limit is used up for now. Try again in 5 min.",
    );
  });

  test('maps_groq_rate_limit_under_a_minute_to_one_minute', () {
    expect(
      errorMessageFor(const GroqRateLimitedException(Duration(seconds: 61))),
      "Groq's free limit is used up for now. Try again in 2 min.",
    );
  });

  test('maps_groq_failed', () {
    expect(
      errorMessageFor(const GroqFailedException(500)),
      "Groq couldn't write this script.",
    );
  });

  test('maps_groq_offline', () {
    expect(
      errorMessageFor(const GroqOfflineException()),
      "You're offline. Connect and try again.",
    );
  });

  test('no_person_found_says_the_crop_stays', () {
    expect(
      errorMessageFor(const NoSubjectFoundException()),
      'No person found in this clip. The crop stays where it is.',
    );
  });

  test('a_failed_follow_asks_to_try_again', () {
    expect(
      errorMessageFor(const FollowFailedException('boom')),
      "Couldn't follow the person. Try again.",
    );
  });
}
