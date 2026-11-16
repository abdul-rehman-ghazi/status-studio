import 'dart:math' as math;
import 'dart:typed_data';

import 'package:status_studio/src/features/style/domain/subject_box.dart';

/// MediaPipe's BlazeFace full-range model (spec FR-23, §10 item 12): a square
/// input, one anchor per cell of a 48 × 48 grid, 16 numbers per anchor (the
/// box, then six landmarks this app ignores) and one score per anchor.
const blazeFaceInputSide = 192;
const blazeFaceAnchorCount = _gridSide * _gridSide;
const blazeFaceValuesPerAnchor = 16;

/// MediaPipe's own threshold for this model.
const blazeFaceLeastScore = 0.6;

const _gridSide = 48;

/// Boxes overlapping more than this are one face (MediaPipe's value).
const _sameFaceOverlap = 0.3;

/// MediaPipe clips raw scores here before the sigmoid, so a huge logit can't
/// overflow `exp`.
const _scoreClip = 100.0;

/// Where the frame sits in the square model input after being scaled to fit
/// and centred, in input pixels. The rest of the input is padding.
class Letterbox {
  const Letterbox._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory Letterbox.forFrame({required int width, required int height}) {
    final longSide = math.max(width, height);
    final scaledWidth = math.max(
      1,
      (width * blazeFaceInputSide / longSide).round(),
    );
    final scaledHeight = math.max(
      1,
      (height * blazeFaceInputSide / longSide).round(),
    );
    return Letterbox._(
      left: (blazeFaceInputSide - scaledWidth) ~/ 2,
      top: (blazeFaceInputSide - scaledHeight) ~/ 2,
      width: scaledWidth,
      height: scaledHeight,
    );
  }

  final int left;
  final int top;
  final int width;
  final int height;
}

/// The model's two outputs for one frame and where the frame sat in its
/// input.
class BlazeFaceOutput {
  const BlazeFaceOutput({
    required this.boxes,
    required this.scores,
    required this.letterbox,
  });

  /// [blazeFaceAnchorCount] × [blazeFaceValuesPerAnchor] numbers, in input
  /// pixels relative to each anchor: x centre, y centre, width, height first.
  final Float32List boxes;

  /// [blazeFaceAnchorCount] raw scores (logits).
  final Float32List scores;

  final Letterbox letterbox;
}

class ScoredFace {
  const ScoredFace(this.box, this.score);

  /// As fractions of the frame.
  final SubjectBox box;
  final double score;
}

/// The faces in [output] as fractions of the frame, best first. The many
/// overlapping boxes the model gives for one face are merged into one box,
/// their average weighted by score, as MediaPipe does.
List<ScoredFace> scoredFacesFrom(BlazeFaceOutput output) {
  final candidates = _candidatesIn(output);
  return [
    for (final face in _mergedOverlaps(candidates))
      ScoredFace(_withoutLetterbox(face.box, output.letterbox), face.score),
  ];
}

List<SubjectBox> facesFrom(BlazeFaceOutput output) => [
  for (final face in scoredFacesFrom(output)) face.box,
];

/// A box as fractions of the square input.
typedef _Corners = ({double left, double top, double right, double bottom});

typedef _Candidate = ({_Corners box, double score});

List<_Candidate> _candidatesIn(BlazeFaceOutput output) {
  final candidates = <_Candidate>[];
  for (var anchor = 0; anchor < blazeFaceAnchorCount; anchor++) {
    final score = _sigmoid(output.scores[anchor]);
    if (score < blazeFaceLeastScore) {
      continue;
    }
    candidates.add((box: _decoded(output.boxes, anchor), score: score));
  }
  return candidates;
}

double _sigmoid(double logit) =>
    1 / (1 + math.exp(-logit.clamp(-_scoreClip, _scoreClip)));

/// The anchors sit at the centres of the grid's cells and are one input wide
/// (MediaPipe's fixed anchor size), so the offsets only need scaling.
_Corners _decoded(Float32List boxes, int anchor) {
  final offset = anchor * blazeFaceValuesPerAnchor;
  final anchorX = (anchor % _gridSide + 0.5) / _gridSide;
  final anchorY = (anchor ~/ _gridSide + 0.5) / _gridSide;
  final centreX = boxes[offset] / blazeFaceInputSide + anchorX;
  final centreY = boxes[offset + 1] / blazeFaceInputSide + anchorY;
  final halfWidth = boxes[offset + 2] / blazeFaceInputSide / 2;
  final halfHeight = boxes[offset + 3] / blazeFaceInputSide / 2;
  return (
    left: centreX - halfWidth,
    top: centreY - halfHeight,
    right: centreX + halfWidth,
    bottom: centreY + halfHeight,
  );
}

List<_Candidate> _mergedOverlaps(List<_Candidate> candidates) {
  final remaining = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
  final merged = <_Candidate>[];
  while (remaining.isNotEmpty) {
    final best = remaining.first;
    final sameFace = [
      for (final candidate in remaining)
        if (_overlap(best.box, candidate.box) > _sameFaceOverlap) candidate,
    ];
    remaining.removeWhere(sameFace.contains);
    merged.add((box: _weightedBox(sameFace), score: best.score));
  }
  return merged;
}

/// Intersection over union.
double _overlap(_Corners a, _Corners b) {
  final width = math.min(a.right, b.right) - math.max(a.left, b.left);
  final height = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (width <= 0 || height <= 0) {
    return 0;
  }
  final shared = width * height;
  return shared / (_area(a) + _area(b) - shared);
}

double _area(_Corners box) => (box.right - box.left) * (box.bottom - box.top);

_Corners _weightedBox(List<_Candidate> sameFace) {
  var totalScore = 0.0;
  var left = 0.0;
  var top = 0.0;
  var right = 0.0;
  var bottom = 0.0;
  for (final candidate in sameFace) {
    totalScore += candidate.score;
    left += candidate.box.left * candidate.score;
    top += candidate.box.top * candidate.score;
    right += candidate.box.right * candidate.score;
    bottom += candidate.box.bottom * candidate.score;
  }
  return (
    left: left / totalScore,
    top: top / totalScore,
    right: right / totalScore,
    bottom: bottom / totalScore,
  );
}

SubjectBox _withoutLetterbox(_Corners box, Letterbox letterbox) {
  double alongX(double inputFraction) =>
      ((inputFraction * blazeFaceInputSide - letterbox.left) / letterbox.width)
          .clamp(0.0, 1.0);
  double alongY(double inputFraction) =>
      ((inputFraction * blazeFaceInputSide - letterbox.top) / letterbox.height)
          .clamp(0.0, 1.0);
  final left = alongX(box.left);
  final top = alongY(box.top);
  return SubjectBox(
    left: left,
    top: top,
    width: alongX(box.right) - left,
    height: alongY(box.bottom) - top,
  );
}
