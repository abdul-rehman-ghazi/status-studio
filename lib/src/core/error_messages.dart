import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/youtube_link.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/topic/domain/topic_errors.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Spec §8 copy for a failure from the data layer.
String errorMessageFor(Object error) {
  return switch (error) {
    OfflineException() ||
    GroqOfflineException() => "You're offline. Connect and try again.",
    InsufficientStorageException() => 'Not enough space on your phone.',
    VideoUnreadableException() => "Can't read this video.",
    VideoUnavailableException() => "This video can't be downloaded.",
    InvalidYouTubeLinkException() => "That doesn't look like a YouTube link.",
    YouTubeChangedException() =>
      "Couldn't read this video from YouTube. Update the downloader in "
          'Settings, or try again later.',
    VideoNotConvertibleException() =>
      "This phone can't convert this AV1 video. Save it as H.264 (MP4) in "
          'your editor and share it again.',
    KeptVideoMissingException() => 'Video not found, choose it again.',
    NoSpeechFoundException() => 'No speech found in this video.',
    NoGroqKeyException() => 'Writing a script needs a free Groq key.',
    NoGroqConsentException() =>
      'Writing a script needs your OK to send the audio to Groq.',
    GroqKeyRejectedException() => "Groq didn't accept your API key.",
    GroqRateLimitedException(:final retryAfter) => _groqLimitMessage(
      retryAfter,
    ),
    GroqFailedException() => "Groq couldn't write this script.",
    LyricsNotTranslatedException() => "Groq couldn't translate the lyrics.",
    RenderFailedException() => "Couldn't make the reel.",
    LinkTooLongException() =>
      'This video is too long. Links can be up to 3 hours with captions, '
          'or 2 hours without.',
    NoMomentsFoundException() =>
      "Couldn't find this topic in the video. Try other words or a longer "
          'video.',
    GroqDailyLimitException() =>
      "Groq's free daily limit is used up. Try again tomorrow, or use a key "
          "on Groq's paid plan.",
    GroqUnreadableReplyException() =>
      "Groq's answer couldn't be read. Try again.",
    FollowFailedException() => "Couldn't follow the person. Try again.",
    NotDownloadableInPartsException() =>
      "This video can't be downloaded in parts.",
    JoinFailedException() => "Couldn't join the cuts.",
    CutsNotDecodableException() => "This phone can't convert this AV1 video.",
    _ => 'Something went wrong. Try again.',
  };
}

String _groqLimitMessage(Duration retryAfter) {
  final minutes = (retryAfter.inSeconds / 60).ceil();
  return "Groq's free limit is used up for now. Try again in $minutes min.";
}
