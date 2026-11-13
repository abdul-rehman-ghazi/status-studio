import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/join/domain/joined_cut.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';

/// What a clip joined from a link keeps beside its video (spec FR-37):
/// where it came from and where its cuts meet. A `topic` written before
/// M53 is ignored (FR-43).
@immutable
class LinkedClip {
  const LinkedClip({
    required this.youtubeId,
    required this.title,
    required this.channel,
    required this.outputLanguage,
    required this.transition,
    required this.joinTimes,
    required this.cuts,
  });

  /// Throws [FormatException] for a JSON that isn't a saved linked clip.
  factory LinkedClip.fromJson(Map<String, Object?> json) {
    if (json case {
      'youtubeId': final String youtubeId,
      'title': final String title,
      'channel': final String channel,
      'outputLanguage': final String languageCode,
      'transition': final String transitionName,
      'joinTimesMs': final List<Object?> joinTimesMs,
    }) {
      return LinkedClip(
        youtubeId: youtubeId,
        title: title,
        channel: channel,
        outputLanguage: _languageOf(languageCode),
        transition: _transitionOf(transitionName),
        joinTimes: [
          for (final time in joinTimesMs)
            if (time is int) Duration(milliseconds: time),
        ],
        // A clip joined before M54 kept no cut times (spec FR-44).
        cuts: switch (json['cuts']) {
          final List<Object?> cuts => cuts.map(JoinedCut.fromJson).toList(),
          _ => const [],
        },
      );
    }
    throw const FormatException('Not a saved linked clip.');
  }

  final String youtubeId;
  final String title;
  final String channel;

  /// What the lyrics are written in (spec FR-37).
  final ScriptLanguage outputLanguage;
  final ClipTransition transition;

  /// Where each cut gives way to the next, in the joined video's time:
  /// scene edges for the crop (FR-27).
  final List<Duration> joinTimes;

  /// Each cut's source and joined times; empty for a clip joined before
  /// M54.
  final List<JoinedCut> cuts;

  Map<String, Object?> toJson() => {
    'youtubeId': youtubeId,
    'title': title,
    'channel': channel,
    'outputLanguage': outputLanguage.whisperCode,
    'transition': transition.name,
    'joinTimesMs': [for (final time in joinTimes) time.inMilliseconds],
    'cuts': [for (final cut in cuts) cut.toJson()],
  };
}

ScriptLanguage _languageOf(String code) {
  for (final language in ScriptLanguage.values) {
    if (language.whisperCode == code) {
      return language;
    }
  }
  throw FormatException('Unknown language $code.');
}

ClipTransition _transitionOf(String name) {
  for (final transition in ClipTransition.values) {
    if (transition.name == name) {
      return transition;
    }
  }
  throw FormatException('Unknown transition $name.');
}
