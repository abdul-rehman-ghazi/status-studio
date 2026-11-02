import 'package:flutter/material.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/features/style/domain/caption_font.dart';

/// Transcript or caption text in the right font, direction and line height
/// for its script.
class ScriptText extends StatelessWidget {
  const ScriptText(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;

  /// When set, text beyond it ends in an ellipsis.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final rightToLeft = isArabicScript(text);
    return Text(
      text,
      textAlign: rightToLeft ? TextAlign.right : TextAlign.left,
      textDirection: rightToLeft ? TextDirection.rtl : TextDirection.ltr,
      style: scriptTextStyle(text).merge(style),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

TextStyle scriptTextStyle(String text) {
  return TextStyle(
    fontFamily: captionFontFamily(text),
    height: captionLineHeight(text),
  );
}
