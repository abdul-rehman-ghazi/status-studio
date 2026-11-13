import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/style/data/body_model.dart';
import 'package:status_studio/src/features/style/data/face_model.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

abstract interface class SubjectDetector {
  /// The faces in the JPEG [frame], as fractions of it; none is an empty
  /// list.
  Future<List<SubjectBox>> facesIn(File frame);

  /// The people in the JPEG [frame] as body boxes, as fractions of it; none
  /// is an empty list (spec FR-27).
  Future<List<SubjectBox>> bodiesIn(File frame);

  Future<void> close();
}

/// BlazeFace full range for faces and EfficientDet-Lite0 for bodies, both
/// on the phone through TensorFlow Lite (spec FR-23, FR-27; ML Kit until
/// M47). Each is set up on first use, so a run that only looks at faces never
/// loads the body model.
class OnDeviceDetector implements SubjectDetector {
  Future<FaceModel>? _faces;
  Future<BodyModel>? _bodies;

  @override
  Future<List<SubjectBox>> facesIn(File frame) async {
    final model = await (_faces ??= FaceModel.open());
    return model.facesIn(frame);
  }

  @override
  Future<List<SubjectBox>> bodiesIn(File frame) async {
    final model = await (_bodies ??= BodyModel.open());
    return model.peopleIn(frame);
  }

  @override
  Future<void> close() async {
    final faces = _faces;
    if (faces != null) {
      await _closeQuietly(() async => (await faces).close());
    }
    final bodies = _bodies;
    if (bodies != null) {
      await _closeQuietly(() async => (await bodies).close());
    }
  }

  /// A model that never opened has nothing to close, and its failure was
  /// already reported by the call that needed it; closing must not throw it
  /// again and end a run that can go on with the other model and spots.
  Future<void> _closeQuietly(Future<void> Function() closeModel) async {
    try {
      await closeModel();
    } on Object {
      return;
    }
  }
}

/// Makes a detector for one run. The run closes it, so the native models are
/// not held between runs.
final subjectDetectorProvider = Provider<SubjectDetector Function()>(
  (ref) => OnDeviceDetector.new,
);
