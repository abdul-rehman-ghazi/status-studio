import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

const _version = 1;

/// A link left on Review cuts, continued from Recent (spec FR-38).
@immutable
class LinkSession {
  const LinkSession({
    required this.request,
    required this.cuts,
    required this.transition,
    required this.edited,
    required this.savedAt,
  });

  /// Throws [FormatException] when [json] isn't a version 1 session.
  factory LinkSession.fromJson(Map<String, Object?> json) => switch (json) {
    {
      'version': _version,
      'request': final Map<String, Object?> request,
      'cuts': final List<Object?>? cuts,
      'transition': final String transition,
      'edited': final bool edited,
      'savedAt': final String savedAt,
    } =>
      LinkSession(
        request: _requestFromJson(request),
        cuts: cuts?.map(_reviewCutFromJson).toList(),
        transition: _transitionOf(transition),
        edited: edited,
        savedAt: DateTime.parse(savedAt),
      ),
    _ => throw const FormatException('Not a version 1 link session.'),
  };

  final TopicRequest request;

  /// In the list's order; null while the moments are still being found.
  final List<ReviewCut>? cuts;
  final ClipTransition transition;

  /// Whether the user changed the found cuts. Find again asked first until
  /// it left the app bar (M49, FR-40); kept so older sessions still read.
  final bool edited;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    'version': _version,
    'request': _requestToJson(request),
    'cuts': cuts?.map(_reviewCutToJson).toList(),
    'transition': transition.name,
    'edited': edited,
    'savedAt': savedAt.toUtc().toIso8601String(),
  };
}

Map<String, Object?> _requestToJson(TopicRequest request) => {
  'video': _videoToJson(request.video),
  'topic': request.topic,
  'lengthMs': request.length.inMilliseconds,
  'outputLanguage': request.outputLanguage.whisperCode,
};

TopicRequest _requestFromJson(Map<String, Object?> json) => switch (json) {
  {
    'video': final Map<String, Object?> video,
    'topic': final String topic,
    'lengthMs': final int lengthMs,
    'outputLanguage': final String language,
  } =>
    TopicRequest(
      video: _videoFromJson(video),
      topic: topic,
      length: Duration(milliseconds: lengthMs),
      outputLanguage: _languageOf(language),
    ),
  _ => throw const FormatException('Not a topic request.'),
};

Map<String, Object?> _videoToJson(LinkedVideo video) => {
  'id': video.videoId,
  'title': video.title,
  'channel': video.channel,
  'durationMs': video.duration.inMilliseconds,
  'thumbnailUrl': video.thumbnailUrl,
  'captionsUrl': video.captionsUrl,
};

LinkedVideo _videoFromJson(Map<String, Object?> json) => switch (json) {
  {
    'id': final String id,
    'title': final String title,
    'channel': final String channel,
    'durationMs': final int durationMs,
    'thumbnailUrl': final String? thumbnailUrl,
    'captionsUrl': final String? captionsUrl,
  } =>
    LinkedVideo(
      videoId: id,
      title: title,
      channel: channel,
      duration: Duration(milliseconds: durationMs),
      thumbnailUrl: thumbnailUrl,
      captionsUrl: captionsUrl,
    ),
  _ => throw const FormatException('Not a linked video.'),
};

Map<String, Object?> _reviewCutToJson(ReviewCut review) => {
  'startMs': review.cut.start.inMilliseconds,
  'endMs': review.cut.end.inMilliseconds,
  'text': review.cut.text,
  'reason': review.cut.reason,
  'ticked': review.ticked,
  'needsWords': review.needsWords,
};

ReviewCut _reviewCutFromJson(Object? json) => switch (json) {
  {
    'startMs': final int startMs,
    'endMs': final int endMs,
    'text': final String text,
    'reason': final String reason,
    'ticked': final bool ticked,
  } =>
    ReviewCut(
      cut: TopicCut(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
        text: text,
        reason: reason,
      ),
      ticked: ticked,
      // Sessions kept before M49 have no mark.
      needsWords: json['needsWords'] == true,
    ),
  _ => throw const FormatException('Not a review cut.'),
};

ScriptLanguage _languageOf(String code) {
  for (final language in outputLanguages) {
    if (language.whisperCode == code) {
      return language;
    }
  }
  throw FormatException('Not an output language: $code.');
}

ClipTransition _transitionOf(String name) {
  for (final transition in ClipTransition.values) {
    if (transition.name == name) {
      return transition;
    }
  }
  throw FormatException('Unknown transition $name.');
}
