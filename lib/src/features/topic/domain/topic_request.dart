import 'package:status_studio/src/features/source/domain/linked_video.dart';

/// What the user asked for on Source (spec FR-36).
class TopicRequest {
  const TopicRequest({
    required this.video,
    required this.topic,
    required this.length,
  });

  final LinkedVideo video;

  /// As typed, in any language.
  final String topic;

  /// The clip's length; the cuts add up to 90–110 % of it.
  final Duration length;
}

const _longestWithCaptions = Duration(hours: 3);
const _longestWithoutCaptions = Duration(hours: 2);
const _warnWithoutCaptions = Duration(hours: 1);

/// Without captions the whole audio goes to Groq, which has an hourly
/// audio allowance of two hours (§12 M43–M47 design).
bool isTooLongForTopics(LinkedVideo video) =>
    video.duration >
    (video.captionsUrl == null
        ? _longestWithoutCaptions
        : _longestWithCaptions);

/// Review cuts asks first before Groq writes a long script (spec FR-36).
bool needsLongScriptWarning(LinkedVideo video) =>
    video.captionsUrl == null && video.duration > _warnWithoutCaptions;
