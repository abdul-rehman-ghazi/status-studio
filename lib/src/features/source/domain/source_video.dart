import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:status_studio/src/core/json_converters.dart';

part 'source_video.freezed.dart';
part 'source_video.g.dart';

/// A video the user brought in (spec FR-1): its ID is the file fingerprint
/// (`v_<16 hex>`) and its title the file name.
@freezed
abstract class SourceVideo with _$SourceVideo {
  const factory SourceVideo({
    required String videoId,
    required String title,
    @JsonKey(name: 'durationMs')
    @MillisecondsConverter()
    required Duration duration,

    /// The earliest a clip can start: where the picture begins, rounded up
    /// to a tenth of a second (spec FR-5, M41). A video saved before M41
    /// has none, so it reads as zero.
    @JsonKey(name: 'pictureStartMs')
    @MillisecondsConverter()
    @Default(Duration.zero)
    Duration pictureStart,
  }) = _SourceVideo;

  /// Throws [CheckedFromJsonException] when [json] isn't a saved video. A
  /// `channel` key left by an older version is ignored.
  factory SourceVideo.fromJson(Map<String, Object?> json) =>
      _$SourceVideoFromJson(json);
}
