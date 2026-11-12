import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// One timed caption from a YouTube track (spec FR-36).
@immutable
class CaptionCue {
  const CaptionCue({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is CaptionCue &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);
}

/// The `json3` URL of the track the topic search reads, or null when the
/// video has none worth reading (spec FR-36): an uploaded track, in the
/// video's language when YouTube names one, else the auto-generated track
/// in the spoken language (`<code>-orig`). Machine translations are never
/// picked: they are a second guess on top of the first.
String? pickTopicCaptionUrl(Map<String, Object?> info) {
  final uploaded = _tracksOf(info['subtitles'])..remove('live_chat');
  final language = info['language'];
  final uploadedKey = uploaded.containsKey(language)
      ? language! as String
      : uploaded.keys.firstOrNull;
  if (uploadedKey != null) {
    return _json3Url(uploaded[uploadedKey]);
  }
  final automatic = _tracksOf(info['automatic_captions']);
  final spokenKey = automatic.keys
      .where((key) => key.endsWith('-orig'))
      .firstOrNull;
  return spokenKey == null ? null : _json3Url(automatic[spokenKey]);
}

Map<String, Object?> _tracksOf(Object? tracks) =>
    tracks is Map<String, Object?> ? Map.of(tracks) : <String, Object?>{};

String? _json3Url(Object? formats) {
  if (formats is! List<Object?>) {
    return null;
  }
  final json3 = formats.whereType<Map<String, Object?>>().where(
    (format) => format['ext'] == 'json3',
  );
  final url = json3.firstOrNull?['url'];
  return url is String ? url : null;
}

/// YouTube's `json3` caption format: `events`, each with a start, a length
/// and text split into `segs`. Events without `segs` only set up the
/// caption window and aren't captions.
List<CaptionCue> captionsFromJson3(Map<String, Object?> json) {
  final events = (json['events'] as List<Object?>? ?? const [])
      .whereType<Map<String, Object?>>()
      .where((event) => event['segs'] is List<Object?>);
  return [for (final event in events) _cueOf(event)];
}

CaptionCue _cueOf(Map<String, Object?> event) {
  final start = (event['tStartMs'] as num? ?? 0).toInt();
  final length = (event['dDurationMs'] as num? ?? 0).toInt();
  final text = (event['segs']! as List<Object?>)
      .whereType<Map<String, Object?>>()
      .map((segment) => segment['utf8'] as String? ?? '')
      .join();
  return CaptionCue(
    text: text,
    start: Duration(milliseconds: start),
    end: Duration(milliseconds: start + length),
  );
}

/// Each caption with words in it becomes one line, numbered in order.
List<TranscriptLine> linesFromCaptions(List<CaptionCue> cues) {
  final spoken = cues
      .map((cue) => (cue: cue, text: _spokenText(cue.text)))
      .where((entry) => entry.text.isNotEmpty)
      .toList();
  return [
    for (final (index, entry) in spoken.indexed)
      TranscriptLine(
        index: index,
        text: entry.text,
        start: entry.cue.start,
        end: entry.cue.end,
      ),
  ];
}

final _musicSymbols = RegExp('[♪♫♬♩]');
final _soundTag = RegExp(r'^(\[[^\]]*\]|\([^)]*\))$');

/// [caption] without music symbols or line breaks; empty when it only names
/// a sound ("[Music]", "(applause)").
String _spokenText(String caption) {
  final text = caption
      .replaceAll(_musicSymbols, '')
      .replaceAll('\n', ' ')
      .trim();
  return _soundTag.hasMatch(text) ? '' : text;
}
