import 'package:flutter/material.dart';

/// Bold label above a group of controls ("Video", "Size", …). One step
/// above body text (14 sp) and list rows, so a section never reads smaller
/// than what it holds.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  /// For headings that sit in a row with other widgets.
  static TextStyle? styleOf(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: styleOf(context)),
    );
  }
}
