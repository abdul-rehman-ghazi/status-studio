import 'package:flutter/material.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/features/style/domain/caption_font.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Transcript or caption text in the right font, direction and line height
/// for its script.
class ScriptText extends StatelessWidget {
  const ScriptText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final rightToLeft = isArabicScript(text);
    return Text(
      text,
      textAlign: rightToLeft ? TextAlign.right : TextAlign.left,
      textDirection: rightToLeft ? TextDirection.rtl : TextDirection.ltr,
      style: scriptTextStyle(text).merge(style),
    );
  }
}

/// Nastaliq needs a tall line height or its letters collide.
TextStyle scriptTextStyle(String text) {
  final family = captionFontFamily(text);
  return TextStyle(
    fontFamily: family,
    height: family == AppFonts.nastaliq ? 2.1 : 1.3,
  );
}
