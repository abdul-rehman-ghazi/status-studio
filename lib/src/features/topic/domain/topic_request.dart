import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';

/// What the user asked for on From a link or Source (spec FR-43, FR-51):
/// the video and the language its script is written in. There is no topic
/// or length since M53; the joined clip is named after the video's title.
class TopicRequest {
  const TopicRequest({required this.source, required this.outputLanguage});

  final MomentSource source;

  /// What the script and the moments' words are written in (spec FR-36),
  /// and later the clip's lyrics (FR-37). Never [ScriptLanguage.auto].
  final ScriptLanguage outputLanguage;
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

/// The captions the search reads (spec FR-36, M50): only a link's track
/// in the output language. Null sends the audio to Groq, which writes the
/// script in the output language; a local video has none (FR-51).
String? captionsUrlFor(TopicRequest request) => switch (request.source) {
  LinkedMoments(:final video)
      when video.captionsLanguage == request.outputLanguage.whisperCode =>
    video.captionsUrl,
  _ => null,
};

/// Without captions the whole audio goes to Groq, which has an hourly
/// audio allowance of two hours (§12 M43–M47 design).
bool isTooLongForTopics(TopicRequest request) =>
    request.source.duration >
    (captionsUrlFor(request) == null
        ? _longestWithoutCaptions
        : _longestWithCaptions);

/// Review cuts asks first before Groq writes a long script (spec FR-36).
bool needsLongScriptWarning(TopicRequest request) =>
    captionsUrlFor(request) == null &&
    request.source.duration > _warnWithoutCaptions;
