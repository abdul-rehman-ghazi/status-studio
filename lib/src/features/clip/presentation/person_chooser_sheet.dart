import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _tallest = 360.0;

/// A tap this close to a face (in dp) still chooses it, so a small face in a
/// wide shot has a target of at least 48 dp.
const _reach = 24.0;
const _smallestTarget = 48.0;

/// Asks whom the crop should follow: a sampled frame with a numbered outline
/// on every person (spec FR-25). It only calls back; whatever shows it closes
/// it.
class PersonChooserSheet extends StatelessWidget {
  const PersonChooserSheet({
    super.key,
    required this.choosing,
    required this.onChosen,
    required this.onChooseForMe,
    required this.onCancel,
  });

  final FollowChoosing choosing;
  final ValueChanged<PersonChoice> onChosen;
  final VoidCallback onChooseForMe;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Who should the crop follow?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const HintText('Tap a face.'),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _tallest),
                child: AspectRatio(
                  aspectRatio:
                      choosing.pictureSize.width / choosing.pictureSize.height,
                  child: LayoutBuilder(
                    builder: (context, box) => _Picture(
                      key: const Key('person-picture'),
                      choosing: choosing,
                      size: box.biggest,
                      onChosen: onChosen,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // A wrap, not a row: on a 320 dp phone the two buttons don't fit
            // side by side.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                OutlinedButton(
                  onPressed: onChooseForMe,
                  child: const Text('Choose for me'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({
    super.key,
    required this.choosing,
    required this.size,
    required this.onChosen,
  });

  final FollowChoosing choosing;
  final Size size;
  final ValueChanged<PersonChoice> onChosen;

  void _tapAt(Offset tap) {
    final near = _nearestFirst(tap);
    if (near.isNotEmpty) {
      onChosen(near.first);
    }
  }

  /// The choices within reach of [tap], the nearest first.
  List<PersonChoice> _nearestFirst(Offset tap) {
    final reached =
        [
            for (final choice in choosing.choices)
              (choice, _distanceFromFace(choice.face, tap)),
          ].where((entry) => entry.$2 <= _reach).toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final entry in reached) entry.$1];
  }

  Rect _rectOf(SubjectBox face) => Rect.fromLTWH(
    face.left * size.width,
    face.top * size.height,
    face.width * size.width,
    face.height * size.height,
  );

  /// 0 inside the face.
  double _distanceFromFace(SubjectBox face, Offset tap) {
    final rect = _rectOf(face);
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
    return GestureDetector(
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
                    const ColoredBox(color: AppColors.surface),
              ),
            ),
          ),
          for (final (index, choice) in choosing.choices.indexed)
            _FaceMarker(
              number: index + 1,
              rect: _rectOf(choice.face),
              onTap: () => onChosen(choice),
            ),
        ],
      ),
    );
  }
}

class _FaceMarker extends StatelessWidget {
  const _FaceMarker({
    required this.number,
    required this.rect,
    required this.onTap,
  });

  final int number;
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
        label: 'Person $number',
        onTap: onTap,
        excludeSemantics: true,
        child: Center(
          child: SizedBox(
            width: rect.width,
            height: rect.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: _NumberBadge(number: number),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          '$number',
          style: const TextStyle(
            color: AppColors.onAccent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
