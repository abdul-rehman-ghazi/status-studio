import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:status_studio/src/core/ffmpeg/jpeg_size.dart';
import 'package:status_studio/src/features/style/domain/blaze_face.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const _modelAsset = 'assets/models/face_detection_full_range.tflite';
const _threads = 4;
const _channels = 3;

/// A frame takes milliseconds; a run that takes this long has died in its
/// isolate, which then never answers.
const _longestInference = Duration(seconds: 15);

/// MediaPipe's BlazeFace full-range model on TensorFlow Lite, on the phone:
/// the faces in a frame as boxes (spec FR-23, §10 item 12). It replaced ML
/// Kit in M47 because F-Droid takes no non-free code. It runs in its own
/// isolate, as the body model does, so it never blocks the screen.
class FaceModel {
  FaceModel._(this._interpreter, this._isolate, this._boxesOutput);

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  /// Which of the model's two outputs holds the boxes; the order is not
  /// fixed between builds of the model, the shapes are.
  final int _boxesOutput;

  static Future<FaceModel> open() async {
    final interpreter = await Interpreter.fromAsset(
      _modelAsset,
      options: InterpreterOptions()..threads = _threads,
    );
    try {
      final boxesOutput = _boxesOutputOf(interpreter);
      final isolate = await IsolateInterpreter.create(
        address: interpreter.address,
      );
      return FaceModel._(interpreter, isolate, boxesOutput);
    } on Object {
      interpreter.close();
      rethrow;
    }
  }

  /// The faces in the JPEG [frame], best first.
  Future<List<SubjectBox>> facesIn(File frame) async =>
      facesFrom(await outputFor(frame));

  /// The model's raw answer for the JPEG [frame].
  Future<BlazeFaceOutput> outputFor(File frame) async {
    final bytes = await frame.readAsBytes();
    final size = jpegSize(bytes);
    final letterbox = Letterbox.forFrame(
      width: size.width,
      height: size.height,
    );
    final input = await _inputOf(bytes, letterbox);
    final boxes = Float32List(blazeFaceAnchorCount * blazeFaceValuesPerAnchor);
    final scores = Float32List(blazeFaceAnchorCount);
    await _isolate
        .runForMultipleInputs(
          [input.buffer.asUint8List()],
          {
            _boxesOutput: boxes.buffer,
            1 - _boxesOutput: scores.buffer,
          },
        )
        .timeout(_longestInference);
    return BlazeFaceOutput(boxes: boxes, scores: scores, letterbox: letterbox);
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}

int _boxesOutputOf(Interpreter interpreter) {
  final outputs = interpreter.getOutputTensors();
  final boxesOutput = outputs.indexWhere(
    (tensor) => tensor.shape.last == blazeFaceValuesPerAnchor,
  );
  if (outputs.length != 2 || boxesOutput < 0) {
    throw StateError('Unexpected face model outputs: $outputs');
  }
  return boxesOutput;
}

/// The frame scaled to fit the square input and centred on black, as RGB
/// values from -1 to 1, the model's input.
Future<Float32List> _inputOf(Uint8List jpeg, Letterbox letterbox) async {
  final rgba = await _scaledRgba(jpeg, letterbox);
  final input = Float32List(
    blazeFaceInputSide * blazeFaceInputSide * _channels,
  )..fillRange(0, blazeFaceInputSide * blazeFaceInputSide * _channels, -1);
  for (var row = 0; row < letterbox.height; row++) {
    for (var column = 0; column < letterbox.width; column++) {
      final from = (row * letterbox.width + column) * 4;
      final to =
          ((row + letterbox.top) * blazeFaceInputSide +
              column +
              letterbox.left) *
          _channels;
      for (var channel = 0; channel < _channels; channel++) {
        input[to + channel] = rgba[from + channel] / 127.5 - 1;
      }
    }
  }
  return input;
}

Future<Uint8List> _scaledRgba(Uint8List jpeg, Letterbox letterbox) async {
  final codec = await ui.instantiateImageCodec(
    jpeg,
    targetWidth: letterbox.width,
    targetHeight: letterbox.height,
  );
  try {
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    return rgba;
  } finally {
    codec.dispose();
  }
}
