// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_video.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SourceVideo _$SourceVideoFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_SourceVideo',
  json,
  ($checkedConvert) {
    final val = _SourceVideo(
      videoId: $checkedConvert('videoId', (v) => v as String),
      title: $checkedConvert('title', (v) => v as String),
      duration: $checkedConvert(
        'durationMs',
        (v) => const MillisecondsConverter().fromJson((v as num).toInt()),
      ),
      pictureStart: $checkedConvert(
        'pictureStartMs',
        (v) => v == null
            ? Duration.zero
            : const MillisecondsConverter().fromJson((v as num).toInt()),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'duration': 'durationMs',
    'pictureStart': 'pictureStartMs',
  },
);

Map<String, dynamic> _$SourceVideoToJson(
  _SourceVideo instance,
) => <String, dynamic>{
  'videoId': instance.videoId,
  'title': instance.title,
  'durationMs': const MillisecondsConverter().toJson(instance.duration),
  'pictureStartMs': const MillisecondsConverter().toJson(instance.pictureStart),
};
