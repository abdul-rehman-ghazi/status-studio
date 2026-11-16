import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

const _version = 2;

/// A video left on Review cuts, continued from Recent (spec FR-38): one per
/// linked video since M53 (FR-43), and one per kept video since M71
/// (FR-51).
@immutable
class LinkSession {
  const LinkSession({
    required this.request,
    required this.cuts,
    required this.transition,
    required this.edited,
    required this.savedAt,
  });

  /// Throws [FormatException] when [json] isn't a version 2 session; a
  /// version 1 one (with a topic, before M53) is unreadable.
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
    _ => throw const FormatException('Not a version 2 link session.'),
  };

  final TopicRequest request;

  /// In the list's order; null while the script is still being fetched.
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
  'video': request.source.toJson(),
  'outputLanguage': request.outputLanguage.whisperCode,
};

TopicRequest _requestFromJson(Map<String, Object?> json) => switch (json) {
  {
    'video': final Map<String, Object?> video,
    'outputLanguage': final String language,
  } =>
    TopicRequest(
      source: MomentSource.fromJson(video),
      outputLanguage: _languageOf(language),
    ),
  _ => throw const FormatException('Not a topic request.'),
};

Map<String, Object?> _reviewCutToJson(ReviewCut review) => {
  'startMs': review.cut.start.inMilliseconds,
  'endMs': review.cut.end.inMilliseconds,
  'text': review.cut.text,
  'ticked': review.ticked,
  'needsWords': review.needsWords,
};

ReviewCut _reviewCutFromJson(Object? json) => switch (json) {
  {
    'startMs': final int startMs,
    'endMs': final int endMs,
    'text': final String text,
    'ticked': final bool ticked,
  } =>
    ReviewCut(
      // A `reason` kept before M53 is ignored (spec FR-43).
      cut: TopicCut(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
        text: text,
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
