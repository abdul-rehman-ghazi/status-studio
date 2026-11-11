import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

// Shares of the font size, so S, M and L cast the same shadow (spec FR-7).
const _tightOffset = 0.04;
const _tightBlur = 0.06;
const _softBlur = 0.18;

/// What the caption is drawn in: the box behind it, if any, the text colour
/// and the shadow it casts (spec FR-7, M37).
@immutable
class CaptionInk {
  const CaptionInk._({required this.text, this.box, this.shadow});

  /// Drawn over the whole caption block; none for the Shadow look.
  final Color? box;
  final Color text;

  /// The colour the text's shadow is cast in; none for the Box look.
  final Color? shadow;

  /// A tight shadow under the letters and a soft one around them, sized
  /// from [fontSize]. Empty for the Box look.
  List<Shadow> shadowsAt(double fontSize) {
    final shadow = this.shadow;
    if (shadow == null) {
      return const [];
    }
    return [
      Shadow(
        color: shadow.withValues(alpha: 0.9),
        offset: Offset(0, fontSize * _tightOffset),
        blurRadius: fontSize * _tightBlur,
      ),
      Shadow(
        color: shadow.withValues(alpha: 0.7),
        blurRadius: fontSize * _softBlur,
      ),
    ];
  }
}

CaptionInk captionInkFor(CaptionAppearance appearance) =>
    switch (appearance.look) {
      CaptionLook.box => _boxInk(appearance.boxColours),
      CaptionLook.shadow => _shadowInk(appearance.shadowColours),
    };

CaptionInk _boxInk(BoxColours colours) => switch (colours) {
  BoxColours.whiteOnBlack => CaptionInk._(
    text: ReelColors.text,
    box: ReelColors.scrim.withValues(alpha: 0.38),
  ),
  BoxColours.blackOnWhite => CaptionInk._(
    text: ReelColors.captionInk,
    box: ReelColors.captionPaper.withValues(alpha: 0.85),
  ),
  BoxColours.yellowOnBlack => CaptionInk._(
    text: ReelColors.captionYellow,
    box: ReelColors.scrim.withValues(alpha: 0.6),
  ),
  BoxColours.whiteOnGreen => CaptionInk._(
    text: ReelColors.text,
    box: ReelColors.captionGreen.withValues(alpha: 0.85),
  ),
};

CaptionInk _shadowInk(ShadowColours colours) => switch (colours) {
  ShadowColours.white => const CaptionInk._(
    text: ReelColors.text,
    shadow: ReelColors.scrim,
  ),
  ShadowColours.yellow => const CaptionInk._(
    text: ReelColors.captionYellow,
    shadow: ReelColors.scrim,
  ),
  ShadowColours.blackGlow => const CaptionInk._(
    text: ReelColors.captionInk,
    shadow: ReelColors.captionPaper,
  ),
  ShadowColours.gold => const CaptionInk._(
    text: ReelColors.captionGold,
    shadow: ReelColors.scrim,
  ),
};
