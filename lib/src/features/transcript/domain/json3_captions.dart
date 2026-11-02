import 'package:status_studio/src/features/transcript/domain/caption_track_choice.dart';

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
