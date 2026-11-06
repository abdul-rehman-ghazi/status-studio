import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:status_studio/src/core/ffmpeg/jpeg_size.dart';
import 'package:status_studio/src/features/style/data/body_model.dart';
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

/// ML Kit face detection with the bundled model and EfficientDet-Lite0 for
/// bodies, both on the phone (spec FR-23, FR-27). Each is set up on first use,
/// so a run that only looks at faces never loads the body model. Faces: fast
/// mode and small faces allowed; no landmarks, contours or smiles.
class OnDeviceDetector implements SubjectDetector {
  FaceDetector? _faces;
  Future<BodyModel>? _bodies;

  @override
  Future<List<SubjectBox>> facesIn(File frame) async {
    final detector = _faces ??= FaceDetector(
      options: FaceDetectorOptions(minFaceSize: 0.05),
    );
    final size = jpegSize(await frame.readAsBytes());
    final faces = await detector.processImage(
      InputImage.fromFilePath(frame.path),
    );
    return [
      for (final face in faces)
        SubjectBox(
          left: face.boundingBox.left / size.width,
          top: face.boundingBox.top / size.height,
          width: face.boundingBox.width / size.width,
          height: face.boundingBox.height / size.height,
        ),
    ];
  }

  @override
  Future<List<SubjectBox>> bodiesIn(File frame) async {
    final model = await (_bodies ??= BodyModel.open());
    return model.peopleIn(frame);
  }

  @override
  Future<void> close() async {
    await _faces?.close();
    final bodies = _bodies;
    if (bodies != null) {
      await _closeBodies(bodies);
    }
  }

  /// A model that never opened has nothing to close, and its failure was
  /// already reported by the call that needed it; closing must not throw it
  /// again and end a run that can go on with faces and spots.
  Future<void> _closeBodies(Future<BodyModel> opening) async {
    try {
      await (await opening).close();
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
