import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/features/style/domain/subject_path.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _tallest = 360.0;

/// The picture's share of the screen's height, so the buttons stay in view.
const _mostOfTheScreen = 0.45;

/// A tap this close to a face (in dp) still chooses it, so a small face in a
/// wide shot has a target of at least 48 dp.
const _reach = 24.0;
const _smallestTarget = 48.0;

/// How long the pin shows where a spot was picked before the next scene.
const _pinShown = Duration(milliseconds: 450);
const _pinSize = 28.0;

/// A marker's number sits in a tag outside its box, so nothing covers the
/// face or body itself (M32).
const _tagHeight = 18.0;
const _tagGap = 2.0;

/// Room kept for a tag at the picture's right edge; "B12" fits.
const _widestTag = 34.0;
const _cornerStroke = 2.0;
const _longestCorner = 12.0;

/// Asks what the crop should keep in frame in one scene: its fullest frame,
/// with a numbered outline on every face and body (spec FR-27). It answers
/// once, through [onAnswered], and whatever shows it closes it with that
/// answer.
class PersonChooserSheet extends StatefulWidget {
  const PersonChooserSheet({
    super.key,
    required this.choosing,
    required this.onAnswered,
  });

  final FollowChoosing choosing;
  final ValueChanged<SceneAnswer> onAnswered;

  @override
  State<PersonChooserSheet> createState() => _PersonChooserSheetState();
}

class _PersonChooserSheetState extends State<PersonChooserSheet> {
  var _answered = false;
  Offset? _pin;
  Timer? _pinTimer;

  @override
  void dispose() {
    _pinTimer?.cancel();
    super.dispose();
  }

  /// True for the first call only: a second tap while the sheet is closing
  /// must not answer again.
  bool _claim() {
    if (_answered) {
      return false;
    }
    _answered = true;
    return true;
  }

  void _answer(SceneAnswer answer) {
    if (_claim()) {
      widget.onAnswered(answer);
    }
  }

  void _pickSpot(Offset spot) {
    if (!_claim()) {
      return;
    }
    setState(() => _pin = spot);
    _pinTimer = Timer(_pinShown, () => _answerSpot(spot));
  }

  /// The sheet may have been closed (a drag, the scrim, Back) while the pin
  /// showed; popping again then would close the screen under it.
  void _answerSpot(Offset spot) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    widget.onAnswered(PickedSpot(x: spot.dx, y: spot.dy));
  }

  @override
  Widget build(BuildContext context) {
    final choosing = widget.choosing;
    final theme = Theme.of(context);
    final tallest = math.min(
      _tallest,
      MediaQuery.sizeOf(context).height * _mostOfTheScreen,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _titleOf(choosing),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const HintText('Tap a face, a body, or the spot to keep in frame.'),
            if (choosing.skippedSceneCount > 0)
              const HintText(
                'This clip has more than $mostScenesFollowed scenes. '
                'The crop follows the first $mostScenesFollowed.',
              ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: tallest),
                child: AspectRatio(
                  aspectRatio:
                      choosing.pictureSize.width / choosing.pictureSize.height,
                  child: LayoutBuilder(
                    builder: (context, box) => _Picture(
                      key: const Key('person-picture'),
                      choosing: choosing,
                      size: box.biggest,
                      pin: _pin,
                      onFace: (index) => _answer(PickedFace(index)),
                      onBody: (index) => _answer(PickedBody(index)),
                      onSpot: _pickSpot,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // A wrap, not a row: on a 320 dp phone the buttons don't fit
            // side by side.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (choosing.sceneIndex > 0)
                  TextButton(
                    onPressed: () => _answer(const WentBack()),
                    child: const Text('Back'),
                  ),
                TextButton(
                  onPressed: () => _answer(const Cancelled()),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _titleOf(FollowChoosing choosing) {
  final span =
      '${formatTimestamp(choosing.sceneStart)}'
      '–${formatTimestamp(choosing.sceneEnd)}';
  return 'Scene ${choosing.sceneIndex + 1} of ${choosing.sceneCount} · $span';
}

class _Picture extends StatelessWidget {
  const _Picture({
    super.key,
    required this.choosing,
    required this.size,
    required this.pin,
    required this.onFace,
    required this.onBody,
    required this.onSpot,
  });

  final FollowChoosing choosing;
  final Size size;
  final Offset? pin;
  final ValueChanged<int> onFace;
  final ValueChanged<int> onBody;

  /// The spot as fractions of the picture.
  final ValueChanged<Offset> onSpot;

  /// A face first, then a body, else the spot itself.
  void _tapAt(Offset tap) {
    final face = _faceNear(tap);
    if (face != null) {
      onFace(face);
      return;
    }
    final body = _bodyAt(tap);
    if (body != null) {
      onBody(body);
      return;
    }
    onSpot(Offset(tap.dx / size.width, tap.dy / size.height));
  }

  /// The nearest face within reach of [tap], by its place in the list.
  int? _faceNear(Offset tap) {
    int? nearest;
    var nearestDistance = _reach;
    for (final (index, face) in choosing.faces.indexed) {
      final distance = _distanceFromBox(face, tap);
      if (distance <= nearestDistance) {
        nearest = index;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  /// The smallest body box that holds [tap]: a person in front of another is
  /// the one meant.
  int? _bodyAt(Offset tap) {
    int? smallest;
    for (final (index, body) in choosing.bodies.indexed) {
      if (!_rectOf(body).contains(tap)) {
        continue;
      }
      if (smallest == null || body.area < choosing.bodies[smallest].area) {
        smallest = index;
      }
    }
    return smallest;
  }

  /// Just above the box, or just below it when there is no room above;
  /// kept inside the picture's width.
  Offset _tagPlaceFor(Rect box) {
    final above = box.top - _tagGap - _tagHeight;
    final top = above >= 0 ? above : box.bottom + _tagGap;
    final left = math.max(0.0, math.min(box.left, size.width - _widestTag));
    return Offset(left, top);
  }

  Rect _rectOf(SubjectBox box) => Rect.fromLTWH(
    box.left * size.width,
    box.top * size.height,
    box.width * size.width,
    box.height * size.height,
  );

  /// 0 inside the box.
  double _distanceFromBox(SubjectBox box, Offset tap) {
    final rect = _rectOf(box);
    final across = math.max(
      0.0,
      math.max(rect.left - tap.dx, tap.dx - rect.right),
    );
    final down = math.max(
      0.0,
      math.max(rect.top - tap.dy, tap.dy - rect.bottom),
    );
    return math.sqrt(across * across + down * down);
  }

  @override
  Widget build(BuildContext context) {
    // The gesture and the image are excluded from semantics: a screen reader
    // would tap them at (0, 0). The markers are the buttons, and the picture
    // offers the centre as an action.
    return Semantics(
      container: true,
      label: 'Scene picture',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Keep the centre'): () =>
            onSpot(const Offset(0.5, 0.5)),
      },
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _tapAt(details.localPosition),
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: Image.file(
                  choosing.picture,
                  fit: BoxFit.fill,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: context.palette.surface),
                ),
              ),
            ),
            for (final (index, body) in choosing.bodies.indexed)
              _Marker(
                style: _bodyStyle(index),
                rect: _rectOf(body),
                onTap: () => onBody(index),
              ),
            for (final (index, face) in choosing.faces.indexed)
              _Marker(
                style: _faceStyle(index),
                rect: _rectOf(face),
                onTap: () => onFace(index),
              ),
            // Tags after every box, so no box's corners are drawn over one.
            for (final (index, body) in choosing.bodies.indexed)
              _Tag(
                style: _bodyStyle(index),
                at: _tagPlaceFor(_rectOf(body)),
                onTap: () => onBody(index),
              ),
            for (final (index, face) in choosing.faces.indexed)
              _Tag(
                style: _faceStyle(index),
                at: _tagPlaceFor(_rectOf(face)),
                onTap: () => onFace(index),
              ),
            if (pin case final spot?) _Pin(at: spot, size: size),
          ],
        ),
      ),
    );
  }
}

_MarkerStyle _bodyStyle(int index) => _MarkerStyle(
  label: 'Body ${index + 1}',
  badge: 'B${index + 1}',
  color: PictureMarkColors.light,
  badgeTextColor: PictureMarkColors.onLight,
);

_MarkerStyle _faceStyle(int index) => _MarkerStyle(
  label: 'Person ${index + 1}',
  badge: '${index + 1}',
  color: PictureMarkColors.accent,
  badgeTextColor: PictureMarkColors.onAccent,
);

/// How a marker reads: to the eye and to a screen reader.
class _MarkerStyle {
  const _MarkerStyle({
    required this.label,
    required this.badge,
    required this.color,
    required this.badgeTextColor,
  });

  final String label;
  final String badge;
  final Color color;
  final Color badgeTextColor;
}

class _Marker extends StatelessWidget {
  const _Marker({required this.style, required this.rect, required this.onTap});

  final _MarkerStyle style;
  final Rect rect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final target = Rect.fromCenter(
      center: rect.center,
      width: math.max(rect.width, _smallestTarget),
      height: math.max(rect.height, _smallestTarget),
    );
    return Positioned.fromRect(
      rect: target,
      child: Semantics(
        button: true,
        label: style.label,
        onTap: onTap,
        excludeSemantics: true,
        child: Center(
          child: SizedBox(
            width: rect.width,
            height: rect.height,
            child: CustomPaint(painter: _CornersPainter(style.color)),
          ),
        ),
      ),
    );
  }
}

/// Only the four corners of a box, so the person inside stays visible.
class _CornersPainter extends CustomPainter {
  const _CornersPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = math.min(_longestCorner, size.shortestSide * 0.3);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _cornerStroke
      ..strokeCap = StrokeCap.round;
    final corners = Path()
      ..moveTo(0, reach)
      ..lineTo(0, 0)
      ..lineTo(reach, 0)
      ..moveTo(size.width - reach, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, reach)
      ..moveTo(size.width, size.height - reach)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - reach, size.height)
      ..moveTo(reach, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - reach);
    canvas.drawPath(corners, paint);
  }

  @override
  bool shouldRepaint(_CornersPainter oldDelegate) => oldDelegate.color != color;
}

/// A marker's number, outside its box. The marker is the screen reader's
/// button, so the tag is hidden from it.
class _Tag extends StatelessWidget {
  const _Tag({required this.style, required this.at, required this.onTap});

  final _MarkerStyle style;
  final Offset at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx,
      top: at.dy,
      height: _tagHeight,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: _Badge(
            text: style.badge,
            color: style.color,
            textColor: style.badgeTextColor,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.textColor,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows where a spot was picked, its tip on the spot.
class _Pin extends StatelessWidget {
  const _Pin({required this.at, required this.size});

  final Offset at;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: const Key('spot-pin'),
      left: at.dx * size.width - _pinSize / 2,
      top: at.dy * size.height - _pinSize,
      child: const IgnorePointer(
        child: ExcludeSemantics(
          child: Icon(
            Icons.location_on,
            size: _pinSize,
            color: PictureMarkColors.accent,
          ),
        ),
      ),
    );
  }
}
