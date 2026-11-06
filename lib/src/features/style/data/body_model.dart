import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const _modelAsset = 'assets/models/efficientdet_lite0.tflite';
const _inputSide = 320;
const _mostDetections = 25;
const _personClass = 0.0;
const _leastScore = 0.4;
const _threads = 4;

/// A frame takes about a quarter of a second; a run that takes this long has
/// died in its isolate, which then never answers.
const _longestInference = Duration(seconds: 15);

/// EfficientDet-Lite0 on TensorFlow Lite, on the phone: the people in a frame
/// as boxes (spec FR-27, §10 item 7). The model has non-max suppression built
/// in and sees the frame squeezed to 320 × 320, so its boxes are fractions of
/// the original frame.
///
/// One inference takes about a quarter of a second on a Redmi Note 11, so it
/// runs in its own isolate and never blocks the screen.
class BodyModel {
  BodyModel._(this._interpreter, this._isolate);

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  static Future<BodyModel> open() async {
    final interpreter = await Interpreter.fromAsset(
      _modelAsset,
      options: InterpreterOptions()..threads = _threads,
    );
    try {
      final isolate = await IsolateInterpreter.create(
        address: interpreter.address,
      );
      return BodyModel._(interpreter, isolate);
    } on Object {
      interpreter.close();
      rethrow;
    }
  }

  /// The people in the JPEG [frame], left to right in no particular order.
  Future<List<SubjectBox>> peopleIn(File frame) async {
    final input = await _rgbOf(frame);
    final boxes = List<double>.filled(
      _mostDetections * 4,
      0,
    ).reshape<double>([1, _mostDetections, 4]);
    final firstScores = List<double>.filled(
      _mostDetections,
      0,
    ).reshape<double>([1, _mostDetections]);
    final secondScores = List<double>.filled(
      _mostDetections,
      0,
    ).reshape<double>([1, _mostDetections]);
    final count = List<double>.filled(1, 0);
    await _isolate
        .runForMultipleInputs(
          [input],
          {0: boxes, 1: firstScores, 2: secondScores, 3: count},
        )
        .timeout(_longestInference);
    return _peopleFrom((
      boxes: boxes,
      firstRow: firstScores,
      secondRow: secondScores,
      count: count.first.toInt(),
    ));
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}

/// The frame as 320 × 320 RGB bytes, the model's input.
Future<Uint8List> _rgbOf(File frame) async {
  final codec = await ui.instantiateImageCodec(
    await frame.readAsBytes(),
    targetWidth: _inputSide,
    targetHeight: _inputSide,
  );
  try {
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    final rgb = Uint8List(_inputSide * _inputSide * 3);
    for (var pixel = 0; pixel < _inputSide * _inputSide; pixel++) {
      rgb[pixel * 3] = rgba[pixel * 4];
      rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1];
      rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2];
    }
    return rgb;
  } finally {
    codec.dispose();
  }
}

/// The model's two `[1, 25]` outputs are the classes (whole numbers) and the
/// scores, in an order that differs between builds of it; the classes are the
/// row whose values are all whole.
typedef _Outputs = ({
  List<Object?> boxes,
  List<Object?> firstRow,
  List<Object?> secondRow,
  int count,
});

List<SubjectBox> _peopleFrom(_Outputs outputs) {
  final count = outputs.count;
  final boxRows = (outputs.boxes.first! as List<Object?>).cast<List<Object?>>();
  final first = (outputs.firstRow.first! as List<Object?>).cast<double>();
  final second = (outputs.secondRow.first! as List<Object?>).cast<double>();
  final firstAreClasses = first
      .take(count)
      .every((value) => value == value.roundToDouble());
  final classes = firstAreClasses ? first : second;
  final scores = firstAreClasses ? second : first;
  return [
    for (var i = 0; i < count && i < _mostDetections; i++)
      if (classes[i] == _personClass && scores[i] >= _leastScore)
        _boxOf(boxRows[i].cast<double>()),
  ];
}

/// The model gives [top, left, bottom, right] as fractions.
SubjectBox _boxOf(List<double> yxyx) {
  final top = yxyx[0].clamp(0.0, 1.0);
  final left = yxyx[1].clamp(0.0, 1.0);
  final bottom = yxyx[2].clamp(0.0, 1.0);
  final right = yxyx[3].clamp(0.0, 1.0);
  return SubjectBox(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
  );
}
