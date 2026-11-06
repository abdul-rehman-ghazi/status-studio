import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/face_tracks.dart';

/// What the user chose to keep in frame for one scene (spec FR-27). The app
/// never makes this choice for them.
@immutable
sealed class SceneChoice {
  const SceneChoice();
}

/// A face, followed through its scene.
class FollowFace extends SceneChoice {
  const FollowFace(this.track);

  final FaceTrack track;
}

/// A body, followed through its scene. Its boxes are tracked by the same
/// rule as faces; there is no body detector until M25 task 5.
class FollowBody extends SceneChoice {
  const FollowBody(this.track);

  final FaceTrack track;
}

/// A fixed spot, held for the whole scene.
class HoldSpot extends SceneChoice {
  const HoldSpot(this.anchor);

  final CropAnchor anchor;
}
