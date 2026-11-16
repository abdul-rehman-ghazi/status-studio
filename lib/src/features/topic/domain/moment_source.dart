import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

const _localKind = 'local';

/// Which kind of [MomentSource] a joined clip came from (spec FR-51).
enum MomentSourceKind { link, local }

/// The video Review cuts picks moments from (spec FR-51): a linked video,
/// or a video kept on the phone, which downloads nothing.
@immutable
sealed class MomentSource {
  const MomentSource();

  /// A record without `kind` is a link, so files kept before M71 read
  /// unchanged. Throws [FormatException] for a JSON that is neither.
  factory MomentSource.fromJson(Map<String, Object?> json) {
    if (json['kind'] != _localKind) {
      return LinkedMoments(LinkedVideo.fromJson(json));
    }
    try {
      return LocalMoments(SourceVideo.fromJson(json));
    } on Exception {
      throw const FormatException('Not a kept local video.');
    }
  }

  String get title;
  Duration get duration;

  /// Names the source's folders and records: the link's video key or the
  /// local video's fingerprint.
  String get key;

  MomentSourceKind get kind;

  Map<String, Object?> toJson();
}

class LinkedMoments extends MomentSource {
  const LinkedMoments(this.video);

  final LinkedVideo video;

  @override
  String get title => video.title;

  @override
  Duration get duration => video.duration;

  @override
  String get key => video.videoKey;

  @override
  MomentSourceKind get kind => MomentSourceKind.link;

  @override
  Map<String, Object?> toJson() => video.toJson();

  @override
  bool operator ==(Object other) =>
      other is LinkedMoments && other.video.videoKey == video.videoKey;

  @override
  int get hashCode => video.videoKey.hashCode;
}

/// A kept video's moments (spec FR-51), saved as `{"kind": "local",
/// "videoId": "v_…"}` with the rest of the video's facts beside it, so a
/// session reopens without reading the video again (*Claude's call*).
class LocalMoments extends MomentSource {
  const LocalMoments(this.video);

  final SourceVideo video;

  @override
  String get title => video.title;

  @override
  Duration get duration => video.duration;

  @override
  String get key => video.videoId;

  @override
  MomentSourceKind get kind => MomentSourceKind.local;

  @override
  Map<String, Object?> toJson() => {'kind': _localKind, ...video.toJson()};

  @override
  bool operator ==(Object other) =>
      other is LocalMoments && other.video.videoId == video.videoId;

  @override
  int get hashCode => video.videoId.hashCode;
}
