// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_transcript.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SavedTranscript _$SavedTranscriptFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_SavedTranscript', json, ($checkedConvert) {
      final val = _SavedTranscript(
        transcript: $checkedConvert(
          'transcript',
          (v) =>
              const _TranscriptConverter().fromJson(v as Map<String, Object?>),
          readValue: readWholeObject,
        ),
        source: $checkedConvert('source', (v) => v as String),
        savedAt: $checkedConvert('savedAt', (v) => DateTime.parse(v as String)),
      );
      return val;
    });

_PartialTranscript _$PartialTranscriptFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_PartialTranscript', json, ($checkedConvert) {
      final val = _PartialTranscript(
        completedChunks: $checkedConvert(
          'completedChunks',
          (v) => (v as num).toInt(),
        ),
        lines: $checkedConvert(
          'lines',
          (v) => (v as List<dynamic>)
              .map(
                (e) => const _TranscriptLineConverter().fromJson(
                  e as Map<String, Object?>,
                ),
              )
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PartialTranscriptToJson(
  _PartialTranscript instance,
) => <String, dynamic>{
  'completedChunks': instance.completedChunks,
  'lines': instance.lines.map(const _TranscriptLineConverter().toJson).toList(),
};
