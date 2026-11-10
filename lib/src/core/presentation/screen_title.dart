import 'package:flutter/material.dart';

/// An app bar title that stays on one line and shrinks to the room left,
/// so large text never pushes it onto a cut-off second line (spec §4).
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}
