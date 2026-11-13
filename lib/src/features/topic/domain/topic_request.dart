import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';

/// What the user asked for on Source (spec FR-36).
class TopicRequest {
  const TopicRequest({
    required this.video,
    required this.topic,
    required this.length,
    required this.outputLanguage,
  });

  final LinkedVideo video;

  /// As typed, in any language.
  final String topic;

  /// The clip's length; the cuts add up to 90–110 % of it.
  final Duration length;

  /// What the moments' words and reasons are written in (spec FR-36), and
  /// later the clip's lyrics (FR-37). Never [ScriptLanguage.auto].
  final ScriptLanguage outputLanguage;

  /// What the joined clip is called: the topic, or the video's title when
  /// the script came first without one (spec FR-41).
  String get clipName {
    final typed = topic.trim();
    return typed.isEmpty ? video.title : typed;
  }
}

/// The languages Output language offers: the lyrics' list without
/// automatic detection.
const outputLanguages = [
  ScriptLanguage.urdu,
  ScriptLanguage.arabic,
  ScriptLanguage.punjabi,
  ScriptLanguage.persian,
  ScriptLanguage.hindi,
  ScriptLanguage.bengali,
  ScriptLanguage.english,
];

const _longestWithCaptions = Duration(hours: 3);
const _longestWithoutCaptions = Duration(hours: 2);
const _warnWithoutCaptions = Duration(hours: 1);

/// The captions the search reads (spec FR-36, M50): only a track in the
/// output language. Null sends the audio to Groq, which writes the script
/// in the output language.
String? captionsUrlFor(TopicRequest request) {
  final video = request.video;
  return video.captionsLanguage == request.outputLanguage.whisperCode
      ? video.captionsUrl
      : null;
}

/// Without captions the whole audio goes to Groq, which has an hourly
/// audio allowance of two hours (§12 M43–M47 design).
bool isTooLongForTopics(TopicRequest request) =>
    request.video.duration >
    (captionsUrlFor(request) == null
        ? _longestWithoutCaptions
        : _longestWithCaptions);

/// Review cuts asks first before Groq writes a long script (spec FR-36).
bool needsLongScriptWarning(TopicRequest request) =>
    captionsUrlFor(request) == null &&
    request.video.duration > _warnWithoutCaptions;
