import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:status_studio/src/core/ffmpeg/jpeg_size.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

abstract interface class SubjectDetector {
  /// The faces in the JPEG [frame], as fractions of it; none is an empty
  /// list.
  Future<List<SubjectBox>> facesIn(File frame);

  Future<void> close();
}

/// ML Kit face detection with the bundled model, on the phone (spec FR-23).
/// Fast mode and small faces allowed; no landmarks, contours or smiles.
class MlKitFaceDetector implements SubjectDetector {
  MlKitFaceDetector()
    : _detector = FaceDetector(options: FaceDetectorOptions(minFaceSize: 0.05));

  final FaceDetector _detector;

  @override
  Future<List<SubjectBox>> facesIn(File frame) async {
    final size = jpegSize(await frame.readAsBytes());
    final faces = await _detector.processImage(
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
  Future<void> close() => _detector.close();
}

final subjectDetectorProvider = Provider<SubjectDetector>((ref) {
  final detector = MlKitFaceDetector();
  ref.onDispose(() => unawaited(detector.close()));
  return detector;
});
